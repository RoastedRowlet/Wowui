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

local lookup = {'Evoker-Augmentation','Mage-Frost','Unknown-Unknown','Monk-Brewmaster','Warlock-Demonology','Warrior-Fury','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Paladin-Protection','Paladin-Retribution','Druid-Guardian','Druid-Balance','Druid-Restoration','Monk-Windwalker','Mage-Arcane','Warlock-Destruction','Hunter-BeastMastery','DeathKnight-Unholy','Evoker-Devastation','Warrior-Arms','Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Rogue-Assassination','Monk-Mistweaver','Druid-Feral','Hunter-Marksmanship','Warlock-Affliction','Mage-Fire','DemonHunter-Havoc','Warrior-Protection','Rogue-Outlaw','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAECgYJCAAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ah='Ahava:BAAALgADCgUJBQAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAQJDAABAHgWAA==.Aiyaiyai:BAAALgAECgYJDAAAAA==.',
Aj='Ajani:BAAALgAECgYJCQAAAA==.',
Ak='Akawli:BAAALgAECgIJAwAAAA==.',
Al='Alall:BAAALgAECgMJBgAAAA==.Alauth:BAAALgAECgIJAwAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.',
Am='Aminall:BAAALgAECgQJCgAAAA==.',
An='Anarreth:BAAALgADCgUJCAAAAA==.Andahla:BAAALgADCggJCQAAAA==.Andore:BAABLgAECn8ZAAICAAYJnxf9dwBsAQACAAYJnxf9dwBsAQAAAA==.Anewbyss:BAAALgAECggJDAAAAA==.Angrymurloc:BAAALgAECgcJDgAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgQJBwAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Arlona:BAAALgAECgIJAwABLgAECgYJEAADAAAAAA==.Arms:BAAALgAECgcJDAAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJBQAAAA==.Ashraki:BAAALgAECgEJAQAAAA==.Ashreign:BAAALgAECgkJCQAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAABLgAECn8UAAIEAAYJwRGfNAAPAQAEAAYJwRGfNAAPAQAAAA==.',
At='Atreana:BAABLgAECn8zAAIFAAkJ8xNrMAD+AQAFAAkJ8xNrMAD+AQAAAA==.Attykus:BAABLgAECn8tAAIGAAgJ6xM1MQDoAQAGAAgJ6xM1MQDoAQAAAA==.',
Av='Avalerion:BAAALgAECgQJDAAAAA==.Avij:BAAALgAECgQJBwABLgAECgYJCQADAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Banfultoxxin:BAAALgADCggJDAAAAA==.Barrellroll:BAAALgADCgkJCQAAAA==.Bat:BAAALgAECgQJBwAAAA==.',
Be='Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAIHAAkJTw/sIwDAAQAHAAkJTw/sIwDAAQAAAA==.Bigpoppapump:BAAALgAECgMJBAAAAA==.Bismofungion:BAAALgADCgcJCAAAAA==.',
Bl='Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAIIAAcJ5gYdlgDxAAAIAAcJ5gYdlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8eAAIJAAgJ+Bx+AADfAgAJAAgJ+Bx+AADfAgAuAAQKfyYAAgkACQk+JNgHAAsDAAkACQk+JNgHAAsDAAAA.',
Bo='Bocchi:BAAALgAECgEJAQAAAA==.Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECggJDwAAAA==.Bowdacious:BAAALgAECgMJBQAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAECgYJEgAAAA==.Brasidias:BAAALgADCgQJBAAAAA==.Brumak:BAAALgAECgkJCgAAAA==.Bruno:BAABLgAECn8aAAMKAAkJhBHTDADKAQAKAAkJhBHTDADKAQALAAQJlQUQ+gCfAAAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAECgMJBgAAAA==.',
['Bá']='Báthory:BAABLgAECn8UAAIIAAkJohzKEQCXAgAIAAkJohzKEQCXAgAAAA==.',
Ca='Cal:BAAALgAECgYJCwABLgAECggJNQAEAPAdAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAABLgAECn81AAIEAAgJ8B1qDABQAgAEAAgJ8B1qDABQAgAAAA==.Camelshammy:BAAALgAECgYJDgAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJFAACACYTAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAAALgAECgUJDwAAAA==.',
Ce='Cebastian:BAAALgADCgMJAwAAAA==.Cedarpoint:BAAALgADCgcJCAAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAABLgAECn8kAAQMAAgJwxhMEgCOAQANAAgJaBXkHgCiAQAMAAgJQRNMEgCOAQAOAAIJFRG0vQAwAAAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Cheochan:BAAALgADCgYJBgAAAA==.Chizami:BAAALgAECgQJBAABLgAFFAYJEgAHAJMQAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8dAAIPAAkJaiBlBwCwAgAPAAkJaiBlBwCwAgAAAA==.',
Ci='Circa:BAABLgAECn8eAAMCAAgJ3RMFWAC4AQACAAgJgxMFWAC4AQAQAAQJWg7dEAC0AAAAAA==.Cithrel:BAABLgAECn8ZAAIRAAkJiQ/gEAAKAQARAAkJiQ/gEAAKAQAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAQAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAADAAAAAA==.Crocklock:BAABLgAECn8YAAIFAAYJDxUQeQAxAQAFAAYJDxUQeQAxAQAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAABLgAECn8vAAMLAAcJ4QdbwQDjAAALAAcJ0AZbwQDjAAAKAAMJ7QV1OABUAAAAAA==.Damnatio:BAABLgAECn8gAAILAAkJmSTnCgD0AgALAAkJmSTnCgD0AgAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Darkclement:BAABLgAECn8VAAISAAcJsx71KgAIAgASAAcJsx71KgAIAgABLgAFFAMJCQALAE4TAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.Darkwiz:BAAALgAECgUJBQAAAA==.Davrimbasher:BAAALgADCgEJAQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAAALgAECgQJCAAAAA==.Deathgriped:BAAALgAECgUJDgAAAA==.Deeper:BAAALgAECgYJEAAAAA==.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgADCgkJCgAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAADAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCgADAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECggJGwARAP0UAA==.Drahalah:BAABLgAECn8eAAITAAgJXR+CLQAmAgATAAgJXR+CLQAmAgAAAA==.Drakeji:BAABLgAECn8zAAMBAAkJ4AmjKgBxAQABAAkJ4AmjKgBxAQAUAAQJKAGhPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAECgkJCQABLgAFFAUJEgAVAHUcAA==.',
Du='Dumplingg:BAAALgAECggJDAAAAA==.',
Ea='Earthvoodoo:BAAALgAECgYJDwAAAA==.',
Eb='Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgAECgUJBQADAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgUJDAAAAA==.',
Ei='Eillea:BAAALgADCgQJBAAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAYJFwALAPEgAA==.Eluneslight:BAAALgAECgEJAQAAAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJLQAGAOsTAA==.',
En='Ender:BAAALgAECgIJAgAAAA==.',
Ep='Epi:BAAALgAECggJEgAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJDgAAAA==.',
Ev='Evianda:BAAALgADCggJBwAAAA==.',
Ez='Ezale:BAAALgAECgkJEwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAgAAAA==.Faramír:BAAALgAECgEJAQAAAA==.Fatébringer:BAAALgAECggJDgAAAA==.',
Fe='Fennek:BAAALgAECggJEwAAAA==.',
Fo='Fourth:BAAALgAECgEJAgABLgAECgcJDAADAAAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Ga='Garaylo:BAACLgAFFH8XAAILAAYJ8SBPCgDDAQALAAYJ8SBPCgDDAQAuAAQKfykAAgsACQn1JMACAKwDAAsACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIWAAkJtiLuAgAIAwAWAAkJtiLuAgAIAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJQQAPACciAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAABLgAECn8lAAQTAAgJshJ3eQBKAQATAAgJJRB3eQBKAQAXAAYJNQ3cFQDgAAAYAAIJLRMUPABwAAAAAA==.Gnobolts:BAAALgAECgEJAQAAAA==.Gnobull:BAAALgAECgQJBAAAAA==.Gnochi:BAAALgAECgcJBwAAAA==.Gnudgnimish:BAAALgAECgYJBgABLgAECgkJIQAEADYhAA==.',
Go='Goldenblight:BAAALgAECgIJBQAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Gomper:BAAALgAECgMJBAAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAAALgAECgYJDQAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJDQAAAA==.',
Gw='Gwaineedk:BAAALgAECgIJAgAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAADAAAAAA==.Halstron:BAABLgAECn8jAAILAAgJ/x1uJABSAgALAAgJ/x1uJABSAgAAAA==.Harribel:BAABLgAECn8bAAQYAAgJuwX1OQB7AAATAAYJ1wM24wCdAAAYAAQJtwb1OQB7AAAXAAIJ8gHdFgA1AAAAAA==.',
He='Heliòs:BAAALgAECgQJBAAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQZAAkJTRXRJgDcAQAZAAkJTRXRJgDcAQAaAAMJXgfMJACLAAAJAAEJhA0qugAoAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyzel:BAAALgAECgkJEgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAABLgAECn8hAAIEAAkJNiGDBgC0AgAEAAkJNiGDBgC0AgAAAA==.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAwAAAA==.',
Hy='Hylie:BAACLgAFFH8IAAIFAAMJmwVLawC+AAAFAAMJmwVLawC+AAAuAAQKfx0AAgUACQlnDVlaALkBAAUACQlnDVlaALkBAAAA.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAUJEgAVAHUcAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
Im='Imsofresh:BAAALgADCgEJAQAAAA==.',
In='Inte:BAAALgADCgYJBgAAAA==.',
Iz='Izgin:BAABLgAECn8UAAICAAYJJhOLoAAgAQACAAYJJhOLoAAgAQAAAA==.',
Ja='Jadeyn:BAAALgADCgMJAwAAAA==.Jaime:BAAALgADCgYJCQABLgAECgYJCAADAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgADAAAAAA==.Jantar:BAABLgAECn8bAAIOAAkJ4xjJEwCLAgAOAAkJ4xjJEwCLAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAABLgAECn8bAAIZAAYJBhGTPAATAQAZAAYJBhGTPAATAQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAAALgAECgYJDQAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwADAAAAAA==.',
Ju='Jugsy:BAAALgAECgcJEQAAAA==.Juliza:BAAALgADCgQJBAAAAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaligo:BAABLgAECn8+AAMZAAkJLxrfDwBPAgAZAAkJLxrfDwBPAgAaAAQJrgSuIgCrAAAAAA==.Kalistus:BAABLgAECn8WAAIIAAgJxAw0YABEAQAIAAgJxAw0YABEAQAAAA==.Kallistos:BAAALgAECgEJAQABLgAECggJNQAEAPAdAA==.Kalygos:BAAALgADCgkJEAABLgAECggJNQAEAPAdAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgAECgQJBAAAAA==.Katar:BAAALgADCgMJAwAAAA==.Katreset:BAAALgAECgUJCAAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn8zAAIPAAkJriP9AgAdAwAPAAkJriP9AgAdAwAAAA==.Kegfupanda:BAAALgAECgEJAgAAAA==.Keleion:BAABLgAECn8nAAIIAAcJzhDdbgAfAQAIAAcJzhDdbgAfAQABLgAECgkJEwADAAAAAA==.Kevonjuravis:BAABLgAECn8jAAMEAAYJuQ/gRgDEAAAEAAUJ/Q3gRgDEAAAPAAUJWxC+TACmAAAAAA==.',
Kh='Khalya:BAAALgADCgQJBAAAAA==.Khalyl:BAAALgAECgcJDwAAAA==.Kheart:BAAALgAECgEJAQAAAA==.Kholy:BAAALgADCgYJBgAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJGwAAAA==.',
Kl='Kleredan:BAAALgAECgkJBgAAAA==.',
Ko='Koder:BAACLgAFFH8MAAIBAAQJeBanIAAZAQABAAQJeBanIAAZAQAuAAQKfy8ABAEACAmtIbEGABIDAAEACAmtIbEGABIDABQABwkbGeQFANUBABsAAgkOArJEAEoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgAECgUJBQAAAA==.Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kupó:BAAALgADCgUJBQABLgAECgYJDAADAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn81AAMTAAgJUhp6SQDDAQATAAgJUhp6SQDDAQAXAAEJKwlhLgAnAAAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.',
Le='Lecker:BAAALgAECgEJAQAAAA==.Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilbigcow:BAAALgAECgEJAQAAAA==.Lilithxander:BAAALgAECgUJCQAAAA==.Lilshooter:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Lizzybordan:BAAALgAECgUJCAAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.Llarroii:BAAALgAECgEJAQAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAABLgAECn8YAAIcAAYJdBQ+CwBdAQAcAAYJdBQ+CwBdAQAAAA==.Lucy:BAAALgADCgIJAgAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.',
Ly='Lynx:BAAALgAECgEJAwAAAA==.',
Ma='Mariskama:BAABLgAECn8WAAISAAgJLgUvdQAnAQASAAgJLgUvdQAnAQAAAA==.Markusthered:BAAALgAECgMJAwAAAA==.Mazza:BAAALgAECgkJEQAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Mello:BAAALgADCgYJBgAAAA==.Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAWALYiAA==.Metal:BAAALgAECgQJDgAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAAALgAECgUJEAAAAA==.',
Mi='Mikkais:BAAALgAECgUJDAAAAA==.Mimacho:BAAALgAECgQJCAAAAA==.Minimini:BAACLgAFFH8PAAIdAAQJExvKFgBJAQAdAAQJExvKFgBJAQAuAAQKfy4AAh0ACQkJHAgOAIgCAB0ACQkJHAgOAIgCAAAA.Minni:BAAALgAFFAEJAgAAAA==.',
Mo='Moolin:BAABLgAECn8fAAIeAAgJTQbVHQDeAAAeAAgJTQbVHQDeAAAAAA==.Moranthe:BAAALgAECgcJDAABLgAFFAEJAQADAAAAAA==.Mordsyth:BAAALgAECgYJCgAAAA==.',
Mu='Muggni:BAAALgAECgkJEQAAAA==.Muggypew:BAABLgAECn8UAAIfAAkJRgHDJgBiAAAfAAkJRgHDJgBiAAAAAA==.Munder:BAABLgAECn8jAAMgAAgJzxxJBAAmAgAgAAgJmBtJBAAmAgAFAAgJ/xmqRQCzAQAAAA==.Mustymuppet:BAACLgAFFH8NAAIFAAQJFAsKSQARAQAFAAQJFAsKSQARAQAuAAQKfyIAAwUACAmYGSs/AMcBAAUACAmYGSs/AMcBABEAAQlnD7VuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAABLgAECn8aAAIhAAgJAhbFAgDjAQAhAAgJAhbFAgDjAQAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAABLgAECn8ZAAITAAgJwiL+FwCVAgATAAgJwiL+FwCVAgAAAA==.Nemini:BAAALgAECgQJBQAAAA==.Nena:BAABLgAECn8dAAINAAYJbBMCMgAjAQANAAYJbBMCMgAjAQAAAA==.Newfy:BAAALgAECgEJAgABLgAECgEJAwADAAAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAABLgAECn8XAAMUAAYJrApUEgDCAAAUAAQJZgtUEgDCAAABAAIJxwdNgwAoAAAAAA==.Nity:BAAALgAECgQJBAAAAA==.',
No='Noctaurus:BAABLgAECn8YAAITAAgJVgdBfgBBAQATAAgJVgdBfgBBAQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Notagain:BAACLgAFFH8oAAILAAgJnRsdAgCAAgALAAgJnRsdAgCAAgAuAAQKfy4AAgsACQkBI5YHAFoDAAsACQkBI5YHAFoDAAAA.Noxcorvus:BAAALgAECgEJAQAAAA==.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgAECgkJCQAAAA==.Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAAALgAECgUJCgAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwAAAA==.',
Oc='Oceanic:BAAALgADCgYJCwAAAA==.',
Ol='Olenza:BAAALgAECgIJAQAAAA==.Olgreeneyes:BAAALgAECgIJBAAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAIOAAYJChgpTABzAQAOAAYJChgpTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJGgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgADCgYJBgAAAA==.',
Pe='Pebbleshifts:BAAALgAECgIJAgAAAA==.Peejean:BAAALgAECgYJBgAAAA==.Peyblade:BAAALgAECgYJBgABLgAECgkJHgAQABghAA==.Peybreak:BAAALgAECgIJAgABLgAECgkJHgAQABghAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHgAQABghAA==.Peycicle:BAABLgAECn8eAAIQAAkJGCFKAQDOAgAQAAkJGCFKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHgAQABghAA==.Peystruction:BAAALgAECgEJAgABLgAECgkJHgAQABghAA==.Peytan:BAABLgAECn8VAAMIAAkJLxhlHABNAgAIAAkJLxhlHABNAgAiAAEJuQmmdgAuAAABLgAECgkJHgAQABghAA==.Peytin:BAAALgAECgQJBAABLgAECgkJHgAQABghAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAFFAIJAgAAAA==.Pippa:BAABLgAECn8eAAIbAAgJeRskBwBoAgAbAAgJeRskBwBoAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8lAAMJAAkJChzzEQCSAgAJAAkJChzzEQCSAgAZAAEJFgM6nQAcAAAAAA==.',
Po='Poetuck:BAABLgAECn8vAAICAAkJSBKzRADxAQACAAkJSBKzRADxAQAAAA==.Pokeyruler:BAAALgAECgIJAgAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAADAAAAAA==.',
Pr='Proko:BAABLgAECn8eAAMZAAgJ1xILPQAQAQAZAAYJ/hMLPQAQAQAJAAIJYw/UjwBuAAAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBwAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.Purfec:BAAALgADCgYJBgAAAA==.',
Qa='Qatka:BAAALgAECgIJAgAAAA==.',
Qu='Quiver:BAABLgAECn8iAAILAAgJ1Q3AaAB9AQALAAgJ1Q3AaAB9AQAAAA==.Quizle:BAAALgAECgEJAQAAAA==.',
['Qì']='Qìlen:BAAALgAECgcJEQAAAA==.',
Ra='Raein:BAABLgAECn8mAAMJAAcJ7CPBDADKAgAJAAcJ7CPBDADKAgAZAAYJnBcjNwArAQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAAALgAFFAIJBAAAAA==.Rainnsoul:BAAALgAECgYJDgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Ralofurius:BAAALgAECgYJCQAAAA==.Rasril:BAAALgAECgYJDAAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBQAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Renicus:BAAALgADCgYJCAAAAA==.Renmare:BAAALgAECgUJEwAAAA==.Renmore:BAABLgAECn8VAAILAAgJMBHbWgCdAQALAAgJMBHbWgCdAQAAAA==.Reshtargorr:BAAALgADCgIJAgAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBQAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgAECgEJAQAAAA==.Rikeji:BAAALgAECgUJBQAAAA==.Risotto:BAAALgAECgMJBQAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJDAADAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgUJDwAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8iAAISAAYJwA7NeQAdAQASAAYJwA7NeQAdAQAAAA==.Ruele:BAAALgAFFAEJAQAAAA==.Ruenan:BAABLgAECn8sAAMSAAkJxya4AACGAwASAAkJxya4AACGAwAfAAMJlhKzaACcAAAAAA==.',
Ry='Ryain:BAABLgAECn80AAMNAAkJEA/YIwB9AQANAAkJ3g3YIwB9AQAMAAYJVxCcJQDgAAAAAA==.Ryian:BAAALgADCgkJCQAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAIMAAcJNgo/GAD0AAAMAAcJNgo/GAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8UAAIjAAYJXgH0NQB2AAAjAAYJXgH0NQB2AAAAAA==.Sapthat:BAABLgAECn8bAAMkAAcJwyH7AwDqAQAkAAYJAyT7AwDqAQAcAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAABLgAECn8UAAICAAYJiAZXxgDiAAACAAYJiAZXxgDiAAAAAA==.Savemeh:BAAALgAECgEJAQAAAA==.Savepebble:BAABLgAECn8bAAMRAAgJ/RRJGQC5AAAFAAcJ1w4WdQA5AQARAAUJXxdJGQC5AAAAAA==.',
Sc='Scalesofdoom:BAAALgAECgEJAQAAAA==.',
Se='Seather:BAABLgAECn8cAAIlAAgJ4BvDEwB4AgAlAAgJ4BvDEwB4AgAAAA==.Seirin:BAABLgAECn8mAAImAAcJyhUsHAC/AQAmAAcJyhUsHAC/AQAAAA==.Selendaa:BAAALgAECgUJEQAAAA==.Senadarra:BAACLgAFFH8UAAIfAAUJCiHpCgBpAQAfAAUJCiHpCgBpAQAuAAQKfzYAAh8ACQkeISYCAMACAB8ACQkeISYCAMACAAAA.Sephenroth:BAAALgAECgQJBwAAAA==.Sephron:BAAALgAECggJCwAAAA==.Serendipity:BAAALgADCgYJCQABLgAECggJEgADAAAAAA==.Serqet:BAAALgAECgYJDAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shammology:BAAALgAECgcJDwAAAA==.Shaollyn:BAAALgADCgUJCgAAAA==.Sheri:BAABLgAECn8UAAIQAAcJPxoeBACaAQAQAAcJPxoeBACaAQAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAABLgAECn8WAAMOAAYJHRWgPwBxAQAOAAYJHRWgPwBxAQANAAEJaAIJjQAUAAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.Shízu:BAAALgADCgkJCgAAAA==.',
Si='Sillygoose:BAACLgAFFH8cAAICAAcJ2xF1FADnAQACAAcJ2xF1FADnAQAuAAQKfyQAAgIACQlJIJEVACcDAAIACQlJIJEVACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQABLgAECgQJCgADAAAAAA==.Siong:BAAALgADCgcJCgABLgAFFAYJFwALAPEgAA==.Siorknav:BAABLgAECn8fAAILAAgJiQ4BigA7AQALAAgJiQ4BigA7AQAAAA==.',
Sk='Skalar:BAABLgAECn8VAAIGAAcJ4wrHQQAUAQAGAAcJ4wrHQQAUAQAAAA==.Skodah:BAAALgADCgkJEQABLgAECgQJCgADAAAAAA==.',
Sl='Släyr:BAAALgADCgIJAgAAAA==.',
So='Solunara:BAAALgADCgYJFQAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAABLgAECn8ZAAITAAcJ7Q6PfQBCAQATAAcJ7Q6PfQBCAQAAAA==.Sorrenda:BAAALgADCgkJDwAAAA==.Soup:BAABLgAECn8nAAIeAAkJ/g1KDgCbAQAeAAkJ/g1KDgCbAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAABLgAECn8XAAIlAAkJdRkyEAAIAgAlAAkJdRkyEAAIAgAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBwAAAA==.Stkawli:BAAALgAECgMJAwAAAA==.Stovik:BAABLgAECn8qAAMaAAgJ9B3HBwAdAgAaAAgJ9B3HBwAdAgAJAAcJ0RHAOwCNAQAAAA==.',
Sv='Sventhebrave:BAAALgAECgUJEQAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJBgAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgUJBwAAAA==.Sylira:BAACLgAFFH8PAAMmAAYJ5xF+BgCpAQAmAAYJ5xF+BgCpAQAnAAEJMAAZPgATAAAuAAQKfzcAAyYACQmUIsUFAP4CACYACQmUIsUFAP4CACgAAwkWDvBSAI8AAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAADAAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8SAAIVAAUJdRzFDAA4AQAVAAUJdRzFDAA4AQAuAAQKfywAAxUACQlhJGwBADUDABUACQlhJGwBADUDAAYABwkrGsUsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAAALgAECgUJCQAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgQJBAABLgAECggJIgAnAOAMAA==.Tankie:BAAALgADCgEJAQAAAA==.Taurgrim:BAAALgADCgUJBQAAAA==.Tavin:BAAALgAECgEJAgAAAA==.Tazrav:BAAALgAECgMJAwAAAA==.',
Te='Terasha:BAAALgAECgkJBgAAAA==.',
Th='Thalid:BAAALgADCgMJBAAAAA==.Tharonix:BAAALgAECgYJEwAAAA==.Thelil:BAAALgAECgMJAwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgAECgUJBQAAAA==.Thewarden:BAAALgAECgIJAgAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAABLgAECn8wAAICAAkJrBt7IACBAgACAAkJrBt7IACBAgAAAA==.Tinder:BAAALgADCgUJBQABLgAECgYJCAADAAAAAA==.',
Tm='Tmbeesknees:BAAALgADCgMJAwAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.Tusktilldawn:BAAALgAECgQJBAAAAA==.',
Tw='Twohoof:BAAALgADCgkJFAAAAA==.',
Ty='Tydrinor:BAAALgAECgcJAQAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Ug='Ugin:BAAALgAECgUJBgAAAA==.',
Un='Unobasho:BAAALgADCgEJAQABLgAFFAQJBwABAKkNAA==.Unoboxo:BAAALgADCgEJAQABLgAFFAQJBwABAKkNAA==.Unovoke:BAACLgAFFH8HAAIBAAQJqQ2HJgADAQABAAQJqQ2HJgADAQAuAAQKfzQAAgEACQkrHTUPAFMCAAEACQkrHTUPAFMCAAAA.',
Va='Valorash:BAABLgAECn8xAAMLAAkJxiCoDADlAgALAAkJxiCoDADlAgAKAAYJyhu4DwDJAQAAAA==.Valorious:BAAALgAECgEJAQAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgMJBAAAAA==.Velintha:BAAALgAECgcJCAAAAA==.Venatrix:BAAALgAECgYJEQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCgADAAAAAA==.Vessen:BAAALgADCgUJBwAAAA==.',
Vi='Vidascare:BAAALgAECgkJAgAAAA==.Vidu:BAAALgADCgUJBQAAAA==.Vision:BAAALgADCgYJBgAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAABLgAECn8TAAMiAAYJ5QXdNACxAAAiAAYJ5QXdNACxAAAIAAYJcQL+ygBiAAAAAA==.Vonderick:BAAALgADCgkJLgAAAA==.Voodoodog:BAAALgAECgMJBQABLgAECgYJDwADAAAAAA==.',
Vy='Vynlorellas:BAAALgAECgEJAQAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQADAAAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgAECgQJBwABLgAECgUJCAADAAAAAA==.Watongo:BAAALgAECgUJBwAAAA==.Watsaheal:BAAALgADCgIJAgAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQADAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAIaAAcJ5xSuDgDRAQAaAAcJ5xSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAFFAIJAgADAAAAAA==.',
Wy='Wynce:BAAALgAECgUJBQAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgIJAwAAAA==.Xarn:BAABLgAECn8hAAIFAAkJtwdEaQBTAQAFAAkJtwdEaQBTAQAAAA==.',
Xc='Xcïte:BAABLgAECn8XAAQoAAgJwBoPIACeAQAoAAYJ9hwPIACeAQAmAAMJ3RtaWADUAAAnAAUJsg+zRAC2AAAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.',
Ye='Yemon:BAAALgAECgEJAQAAAA==.',
Yo='Yourlock:BAAALgADCgUJBQAAAA==.',
Yu='Yuji:BAABLgAECn80AAILAAkJTRHUPQDuAQALAAkJTRHUPQDuAQAAAA==.',
Za='Zalectra:BAACLgAFFH8SAAIWAAQJHiEECQBjAQAWAAQJHiEECQBjAQAuAAQKfz4AAxYACQm2JUIAAMUDABYACQm2JUIAAMUDAB8AAgmhFmgjAHAAAAAA.',
Ze='Zelila:BAAALgADCgYJCAAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBwAAAA==.',
['Ål']='Ålloria:BAAALgAECgYJDAAAAA==.',
['ßl']='ßlackßetty:BAAALgADCgYJBwABLgADCgkJCQADAAAAAA==.',
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
