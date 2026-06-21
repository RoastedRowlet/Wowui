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

local lookup = {'Evoker-Augmentation','Unknown-Unknown','Shaman-Enhancement','Mage-Frost','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','Monk-Brewmaster','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DemonHunter-Devourer','Shaman-Restoration','Monk-Windwalker','Druid-Balance','Druid-Guardian','Druid-Restoration','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Devastation','Warrior-Arms','DemonHunter-Havoc','DeathKnight-Frost','Shaman-Elemental','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Hunter-Marksmanship','Warlock-Affliction','Mage-Fire','Priest-Holy','Priest-Shadow','Warrior-Protection','Rogue-Outlaw','Priest-Discipline','DemonHunter-Vengeance',}
local provider = {region='US',realm='Gnomeregan',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Acehuntura:BAAALgAECgEJAgAAAA==.',
Ad='Adaric:BAAALgAFFAEJAQAAAA==.',
Af='Afflicea:BAAALgAECgMJAwAAAA==.',
Ah='Ahava:BAAALgAECgQJBwAAAA==.',
Ai='Aidoneiscus:BAAALgAECgUJCgABLgAFFAYJEwABAH4aAA==.Ainokea:BAAALgAECgIJAgABLgAECgYJEwACAAAAAA==.Aiyaiyai:BAAALgAECgYJDQAAAA==.',
Aj='Ajani:BAAALgAECgYJDAAAAA==.',
Ak='Akamini:BAAALgAECgYJBwABLgAFFAMJBwADAA8XAA==.Akawli:BAAALgAECgIJAwAAAA==.',
Al='Alall:BAAALgAECgMJBgAAAA==.Alauth:BAAALgAECgIJAwAAAA==.Aliceandreia:BAAALgADCgUJCgAAAA==.Alliethra:BAAALgAECgUJCQAAAA==.',
Am='Aminall:BAAALgAECgYJDQAAAA==.',
An='Anarreth:BAAALgADCgUJCgAAAA==.Andahla:BAAALgADCgkJCwAAAA==.Andore:BAABLgAECn8kAAIEAAcJfRqjAgBDAQAEAAcJfRqjAgBDAQAAAA==.Anewbyss:BAAALgAFFAEJAQAAAA==.Angrymurloc:BAABLgAECn8aAAMFAAcJTAwXKwBJAQAFAAcJTAwXKwBJAQAGAAUJMQK89gBpAAAAAA==.Anthonie:BAAALgADCgYJBgAAAA==.Antoer:BAAALgAECgIJAgAAAA==.Anwyll:BAAALgADCgcJDAAAAA==.',
Ao='Aoir:BAAALgAECgQJBgAAAA==.',
Ap='Aposthmighty:BAAALgAECgYJEAAAAA==.',
Ar='Arcancis:BAAALgADCgQJBAAAAA==.Ariyia:BAAALgADCgcJBgAAAA==.Arlona:BAAALgAECgIJAwABLgAECgYJEAACAAAAAA==.Arms:BAAALgAECgcJEAAAAA==.Artemyss:BAAALgADCgEJAQAAAA==.',
As='Ashanara:BAAALgAECgQJBAABLgAECgkJNAAHAOoZAA==.Asher:BAAALgADCgEJAQAAAA==.Ashnact:BAAALgAECgIJDAAAAA==.Ashraki:BAAALgAECgEJAQAAAA==.Ashreign:BAAALgAECgkJCQAAAA==.Asl:BAAALgADCgcJBwAAAA==.Asonnari:BAAALgADCgEJAQAAAA==.Astraeal:BAABLgAECn8UAAIIAAYJwRHqPAAIAQAIAAYJwRHqPAAIAQAAAA==.Aswell:BAAALgAECgEJAQAAAA==.',
At='Atreana:BAABLgAECn82AAIJAAkJ4hVPMAAXAgAJAAkJ4hVPMAAXAgAAAA==.Attykus:BAABLgAECn8xAAIKAAgJ/BM1MQDoAQAKAAgJ/BM1MQDoAQAAAA==.',
Av='Avalerion:BAABLgAECn8eAAMLAAkJTxrBIACEAgALAAkJTxrBIACEAgAMAAIJbB3NMgCYAAAAAA==.Avij:BAAALgAECgQJCwABLgAECgYJCQACAAAAAA==.',
Ay='Ayoreo:BAAALgADCgMJAwAAAA==.',
Az='Azmodon:BAAALgADCgEJAwAAAA==.',
['Añ']='Añathema:BAAALgAECgMJBAAAAA==.',
Ba='Baldd:BAAALgAECgYJBgAAAA==.Banfultoxxin:BAAALgADCggJDwAAAA==.Barrellroll:BAAALgADCgkJCQAAAA==.Bastam:BAAALgAECgIJAgABLgAECgIJBQACAAAAAA==.Bat:BAAALgAECgQJBwAAAA==.',
Be='Bearlyhealz:BAAALgADCgkJBQAAAA==.Beercats:BAAALgADCgMJBgAAAA==.Bentotc:BAAALgAECgIJAwAAAA==.',
Bi='Bighoot:BAAALgAECgQJCgAAAA==.Bigmancow:BAABLgAECn8nAAINAAkJTw+8KgC6AQANAAkJTw+8KgC6AQAAAA==.Bigpoppapump:BAAALgAECgQJBgAAAA==.Biomancer:BAAALgAECgYJBgAAAA==.Bismofungion:BAAALgADCgcJEAAAAA==.',
Bl='Bladestalker:BAAALgAECgEJAQAAAA==.Blindmayhem:BAAALgAECgEJAQAAAA==.Bludgens:BAAALgADCgIJAgAAAA==.Bluecoral:BAAALgADCgEJAQAAAA==.Blunter:BAABLgAECn8TAAIOAAcJ5gYdlgDxAAAOAAcJ5gYdlgDxAAAAAA==.Blushtime:BAAALgADCgIJAgAAAA==.Bluwhale:BAACLgAFFH8fAAIPAAgJJB16AgDDAgAPAAgJJB16AgDDAgAuAAQKfyYAAg8ACQk+JIYLAAEDAA8ACQk+JIYLAAEDAAAA.',
Bo='Bocchi:BAAALgAECgEJAQAAAA==.Bodanky:BAAALgAECgMJBQAAAA==.Bormor:BAAALgAECggJEAAAAA==.Bowdacious:BAAALgAECgUJEwAAAA==.Boötes:BAAALgADCgcJBwAAAA==.',
Br='Brago:BAAALgAECgEJAQAAAA==.Braini:BAAALgADCgEJAQAAAA==.Brainpath:BAAALgAFFAIJAgAAAA==.Brasidias:BAAALgAECgYJBgAAAA==.Brickingkeys:BAAALgAECgIJBQAAAA==.Brumak:BAAALgAECgkJCgAAAA==.Bruno:BAABLgAECn8qAAMMAAkJrRhFDQDwAQAMAAkJrRhFDQDwAQALAAQJKQcQ+gCfAAAAAA==.',
Bu='Budthespud:BAAALgAECgEJAQAAAA==.Burland:BAAALgAFFAIJAgAAAA==.',
['Bá']='Báthory:BAABLgAECn8UAAIOAAkJohyMFgCQAgAOAAkJohyMFgCQAgAAAA==.',
Ca='Caedus:BAAALgADCgYJBgAAAA==.Cal:BAAALgAECgYJDAABLgAFFAIJCAAIADMXAA==.Caladin:BAAALgAECgQJBAABLgAFFAIJCAAIADMXAA==.Calamity:BAAALgADCgQJBAAAAA==.Callistos:BAACLgAFFH8IAAIIAAIJMxetQgCaAAAIAAIJMxetQgCaAAAuAAQKfz0AAwgACQmeHnkIAKsCAAgACQmeHnkIAKsCABAAAgkgEX2aADUAAAAA.Camelshammy:BAAALgAECgYJDgAAAA==.Caradyn:BAAALgADCgUJBQABLgAECgYJFAAEACYTAA==.Caris:BAAALgAECgMJAwAAAA==.Castianna:BAABLgAECn8VAAIEAAUJOhCABgCzAAAEAAUJOhCABgCzAAAAAA==.',
Ce='Cebastian:BAAALgAECgYJEwAAAA==.Cedarpoint:BAAALgAECgIJAgAAAA==.Celoria:BAAALgADCgUJCQAAAA==.Century:BAABLgAECn84AAQRAAkJ+xwsEABgAgARAAkJdBosEABgAgASAAgJrBpDEADkAQATAAIJFRGe1AAwAAAAAA==.Cerriwyn:BAAALgAECgEJAQAAAA==.Cery:BAAALgAECgEJAQAAAA==.',
Ch='Cheochan:BAAALgADCgYJDwAAAA==.Chewbaulk:BAAALgAECgkJBgAAAA==.Chizami:BAAALgAECggJDAABLgAFFAgJGAANANEMAA==.Chocostarmie:BAAALgADCgQJBAAAAA==.Chug:BAABLgAECn8eAAIQAAkJlyCvCQCqAgAQAAkJlyCvCQCqAgAAAA==.',
Ci='Circa:BAABLgAECn8qAAMEAAkJhxViQgAUAgAEAAkJOBViQgAUAgAUAAQJWg7dEAC0AAAAAA==.Cithrel:BAABLgAECn8ZAAIVAAkJiQ92FQD/AAAVAAkJiQ92FQD/AAAAAA==.',
Cl='Claylemian:BAAALgAECgMJAwAAAA==.',
Co='Conqubine:BAAALgADCgkJDgAAAA==.Corban:BAAALgAECgEJAwAAAA==.',
Cr='Creolix:BAAALgADCgYJBgABLgAECgYJCAACAAAAAA==.Crocklock:BAABLgAECn8ZAAIJAAcJ6hVHZwBvAQAJAAcJ6hVHZwBvAQAAAA==.',
Cu='Cuddlyblood:BAAALgAECgEJAQAAAA==.Cujo:BAAALgADCgMJAwAAAA==.',
['Cà']='Càssiàn:BAAALgADCgIJAgAAAA==.',
Da='Dallia:BAACLgAFFH8FAAILAAIJ1gFYrABnAAALAAIJ1gFYrABnAAAuAAQKfy8AAwsABwnhB5nlANcAAAsABwnQBpnlANcAAAwAAwntBZZDAFQAAAAA.Damnatio:BAABLgAECn8gAAILAAkJmSRcEQDcAgALAAkJmSRcEQDcAgAAAA==.Damonster:BAAALgAECgIJAwAAAA==.Danossa:BAAALgAECgEJBAAAAA==.Darkclement:BAABLgAECn8VAAIGAAcJsx6XOgD0AQAGAAcJsx6XOgD0AQABLgAFFAMJCQALAE4TAA==.Darkin:BAAALgAECgcJCAAAAA==.Darkmist:BAAALgADCgUJBQAAAA==.Darkwiz:BAABLgAECn8bAAIWAAkJcgffBQCmAAAWAAkJcgffBQCmAAAAAA==.Davrimbasher:BAAALgADCgEJAQAAAA==.',
De='Deadlydk:BAAALgADCgMJAwAAAA==.Deathbybob:BAABLgAECn8ZAAIXAAYJ6hiVHgBhAQAXAAYJ6hiVHgBhAQAAAA==.Deathgriped:BAAALgAECgUJDgAAAA==.Deeper:BAACLgAFFH8FAAIRAAIJ8gFnSQBNAAARAAIJ8gFnSQBNAAAuAAQKfyMAAxEACAlXC743ADYBABEACAlXC743ADYBABMAAwlqAXfdACgAAAAA.Deezmoonz:BAAALgADCgYJCQAAAA==.Dementos:BAAALgADCgkJCgAAAA==.Demonofwar:BAAALgADCgYJDAABLgAECgYJCAACAAAAAA==.Devils:BAAALgAECgUJCQAAAA==.Dezzii:BAAALgAECgIJAgAAAA==.',
Di='Dirin:BAAALgAECgUJDQABLgAECgUJCgACAAAAAA==.Disneymagic:BAAALgADCgUJBwAAAA==.Divacup:BAAALgADCgcJBwAAAA==.',
Dm='Dmaan:BAAALgADCgMJAwAAAA==.',
Do='Doomflower:BAAALgAECgIJAgAAAA==.',
Dr='Dragonpebble:BAAALgADCgYJBgABLgAECgkJHwAJADMUAA==.Drahalah:BAABLgAECn8eAAIWAAgJXR9rOQAaAgAWAAgJXR9rOQAaAgAAAA==.Drakeji:BAABLgAECn81AAMBAAkJWQsqMgBtAQABAAkJWQsqMgBtAQAYAAQJKAGhPwAxAAAAAA==.Dreamliner:BAAALgAECgYJBgAAAA==.Drezind:BAAALgAECgQJBAAAAA==.Drhealalot:BAAALgAECgEJAQAAAA==.Drugar:BAAALgAFFAEJAQABLgAFFAUJEgAZAHUcAA==.',
Du='Dumplingg:BAAALgAECggJDAAAAA==.',
Ea='Earthvoodoo:BAAALgAECgYJDwAAAA==.',
Eb='Eberkenezer:BAAALgAECgQJBAAAAA==.Ebonlight:BAAALgADCgkJFgAAAA==.',
Ec='Ecnyw:BAAALgADCgMJAwABLgAECgUJCAACAAAAAA==.',
Ed='Edence:BAAALgAECgMJAwAAAA==.',
Eh='Ehunter:BAAALgAECgUJDQAAAA==.',
Ei='Eillea:BAAALgADCgQJBAAAAA==.',
El='Elegant:BAAALgAECgkJBwAAAA==.Elspeth:BAAALgAECgIJAgAAAA==.Elsyria:BAAALgADCgIJAgABLgAFFAgJJAALAAEhAA==.Eluneslight:BAAALgAECgEJAwAAAA==.',
Em='Emmeri:BAAALgAECgQJBwABLgAECggJMQAKAPwTAA==.',
En='Ender:BAAALgAECgIJAgAAAA==.',
Ep='Epi:BAABLgAECn8UAAIaAAgJshKtNgDhAAAaAAgJshKtNgDhAAAAAA==.',
Er='Erianis:BAAALgADCgMJAwAAAA==.Erniethemonk:BAAALgAECgYJEAAAAA==.',
Ev='Evianda:BAAALgADCgkJEAAAAA==.',
Ez='Ezale:BAAALgAECgkJEwAAAA==.Ezpz:BAAALgAECgYJEgAAAA==.',
Fa='Falsetto:BAAALgAECgEJAgAAAA==.Fameral:BAAALgAECgEJAgAAAA==.Faramír:BAAALgAECgQJCwAAAA==.Fatébringer:BAAALgAECggJDgABLgAECgcJDgACAAAAAA==.Fauhna:BAAALgAECgEJAQABLgAFFAIJBgALACMiAA==.',
Fe='Fennek:BAABLgAECn8UAAIGAAgJng+zXACPAQAGAAgJng+zXACPAQAAAA==.',
Fi='Fiønaviolet:BAAALgADCgcJBwAAAA==.',
Fo='Fourth:BAAALgAECgIJAwABLgAECgcJEAACAAAAAA==.',
Fr='Frayla:BAAALgADCgEJAQAAAA==.',
Fu='Furrywhenwet:BAAALgAFFAEJAQAAAA==.Fuzzyxbutt:BAAALgAECgYJDgAAAA==.',
Fy='Fyaaga:BAAALgAECgQJBAABLgAFFAYJCwAHADsSAA==.',
Ga='Garaylo:BAACLgAFFH8kAAILAAgJASFhBACgAgALAAgJASFhBACgAgAuAAQKfykAAgsACQn1JMACAKwDAAsACQn1JMACAKwDAAAA.Garroar:BAAALgADCgcJCAAAAA==.',
Ge='Geed:BAAALgADCgEJAQAAAA==.Gewnzilla:BAAALgAECgIJAgAAAA==.',
Gg='Ggxd:BAAALgADCgkJEAAAAA==.',
Gh='Ghosst:BAABLgAECn8jAAIFAAkJtiLuAgAIAwAFAAkJtiLuAgAIAwAAAA==.',
Gi='Gilberticus:BAAALgADCgMJAwABLgAECgkJUAAQAMUiAA==.Gimlithekind:BAAALgAECgEJAQAAAA==.',
Gl='Glen:BAAALgADCgMJAwAAAA==.',
Gn='Gnobliterate:BAABLgAECn8pAAQWAAkJMRLRbgCHAQAWAAkJ9g/RbgCHAQAbAAYJNQ2MHQDhAAAXAAIJLRMuSQBpAAAAAA==.Gnobolts:BAAALgAECgEJAQAAAA==.Gnobull:BAAALgAFFAIJAwAAAA==.Gnochi:BAAALgAECgcJBwAAAA==.Gnudgnimish:BAAALgAFFAIJBAABLgAFFAUJBwAIALkZAA==.',
Go='Goldenblight:BAAALgAECgYJCwAAAA==.Goldenchi:BAAALgAECgEJAQAAAA==.Goldenrage:BAAALgAECgQJBAAAAA==.Goldenshammy:BAAALgAECgEJAQAAAA==.Gomper:BAAALgAECgMJBAAAAA==.Gonforgood:BAAALgADCgYJBgAAAA==.Goonmaxing:BAAALgADCgMJAwAAAA==.Gorilon:BAAALgAECgkJCQAAAA==.',
Gr='Grimclaw:BAAALgADCgYJDgAAAA==.Grimmrot:BAAALgAECgYJEgAAAA==.Grimmz:BAAALgADCggJCQAAAA==.Grizk:BAAALgADCgEJAQAAAA==.',
Gu='Guttris:BAAALgAECgYJEwAAAA==.',
Gw='Gwaineedk:BAAALgAECgMJBAAAAA==.',
Ha='Haikusen:BAAALgADCgYJBAABLgAECgYJCAACAAAAAA==.Halstron:BAACLgAFFH8GAAILAAIJIyJffQC8AAALAAIJIyJffQC8AAAuAAQKfy4AAwsACQm/IAoQAOYCAAsACQmPIAoQAOYCAAwABQl7FeYhAAUBAAAA.Harribel:BAABLgAECn8bAAQXAAgJuwXwRQB2AAAWAAYJ1wM+DwGZAAAXAAQJtwbwRQB2AAAbAAIJ8gHdFgA1AAAAAA==.Hassan:BAAALgAECgIJAgAAAA==.',
He='Heliòs:BAAALgAECgUJCQAAAA==.Hellwár:BAAALgADCgYJBgAAAA==.',
Ho='Hogfu:BAAALgAECgQJBAAAAA==.Hogshock:BAABLgAECn8bAAQcAAkJTRXRJgDcAQAcAAkJTRXRJgDcAQADAAMJXgfMJACLAAAPAAEJhA2B4wAoAAAAAA==.Holocharizrd:BAAALgADCgcJCQAAAA==.Holyrequiem:BAAALgAECgUJBgAAAA==.Holyzel:BAAALgAECgkJEgAAAA==.Hotnsassie:BAAALgADCgMJCQAAAA==.Hound:BAAALgADCgUJCAAAAA==.Hoyt:BAAALgADCgcJBwAAAA==.',
Hs='Hsimingjung:BAACLgAFFH8HAAMIAAUJuRnQGQBWAQAIAAUJuRnQGQBWAQAQAAEJNQt7RAA2AAAuAAQKfykAAwgACQnLITgHAMMCAAgACQnLITgHAMMCABAABAlFIasmAIEBAAAA.',
Hu='Humanic:BAAALgAECgIJAwAAAA==.Huntari:BAAALgAECgEJAwAAAA==.',
Hy='Hylie:BAACLgAFFH8PAAIJAAMJvAqjCwCOAAAJAAMJvAqjCwCOAAAuAAQKfx8AAgkACQnHEFlaALkBAAkACQnHEFlaALkBAAAA.',
['Hè']='Hèlla:BAAALgADCgkJFQAAAA==.',
Ig='Ignisky:BAAALgAECgcJDgABLgAFFAUJEgAZAHUcAA==.',
Il='Illidarie:BAAALgADCgUJCAAAAA==.',
Im='Imsofresh:BAAALgADCgEJAQAAAA==.',
In='Innitchiwa:BAAALgAECgEJAgAAAA==.Inte:BAAALgADCgYJBgAAAA==.Inzi:BAAALgAECgEJAwAAAA==.',
Iz='Izgin:BAABLgAECn8UAAIEAAYJJhN3ugASAQAEAAYJJhN3ugASAQAAAA==.',
Ja='Jadeyn:BAAALgADCgMJAwAAAA==.Jaime:BAAALgADCgYJCQABLgAECgYJCAACAAAAAA==.Jalet:BAAALgADCgcJDQAAAA==.Janie:BAAALgADCgUJCAABLgADCgYJBgACAAAAAA==.Jantar:BAABLgAECn8dAAITAAkJJxrXFwCIAgATAAkJJxrXFwCIAgAAAA==.Jasonbjorne:BAAALgAECgEJAQAAAA==.',
Je='Jebbyclipse:BAAALgAECgQJCAAAAA==.Jenzö:BAABLgAECn8cAAIcAAYJMRKtSQAOAQAcAAYJMRKtSQAOAQAAAA==.Jeramya:BAAALgADCgQJBAAAAA==.',
Jo='Joeviben:BAABLgAECn8aAAILAAcJ6gqqsQAcAQALAAcJ6gqqsQAcAQAAAA==.Jormungandr:BAAALgADCgYJCgABLgADCgcJBwACAAAAAA==.',
Ju='Jugsy:BAABLgAECn8ZAAIEAAkJtBfALgBeAgAEAAkJtBfALgBeAgAAAA==.Juliza:BAAALgADCgQJBAAAAA==.Jungfer:BAAALgAECgMJBAAAAA==.',
['Jë']='Jënzo:BAAALgADCggJCAABLgAECgkJHAAcADESAA==.',
Ka='Kaerodora:BAAALgADCgYJBgAAAA==.Kalasan:BAAALgAECgIJAgAAAA==.Kaldread:BAAALgAECgQJBgAAAA==.Kaligo:BAABLgAECn9CAAMcAAkJQBroFABCAgAcAAkJQBroFABCAgADAAQJrgSuIgCrAAAAAA==.Kalistus:BAABLgAECn8bAAIOAAkJtwxpWQB7AQAOAAkJtwxpWQB7AQAAAA==.Kallistos:BAAALgAECgEJAQABLgAFFAIJCAAIADMXAA==.Kalygos:BAAALgAECgQJBAABLgAFFAIJCAAIADMXAA==.Karall:BAAALgAECgEJAQAAAA==.Karetha:BAAALgAECgUJCQAAAA==.Katar:BAAALgADCgMJAwAAAA==.Katreset:BAAALgAECgUJCAAAAA==.',
Kd='Kdavid:BAAALgADCgUJCgAAAA==.',
Ke='Kebsy:BAABLgAECn87AAIQAAkJPiRbAwAtAwAQAAkJPiRbAwAtAwAAAA==.Kegfupanda:BAAALgAFFAEJAQAAAA==.Keleion:BAABLgAECn8nAAIOAAcJzhDfgwAYAQAOAAcJzhDfgwAYAQABLgAECgkJEwACAAAAAA==.Kelements:BAAALgAFFAEJAQAAAA==.Kelyessada:BAAALgADCgYJBgAAAA==.Kevonjuravis:BAABLgAECn87AAMIAAgJrQ+5KQBmAQAIAAgJuw25KQBmAQAQAAUJWxCiXQChAAAAAA==.',
Kh='Khalya:BAAALgAECgUJBQAAAA==.Khalyl:BAABLgAECn8WAAIaAAUJJRRlNQDoAAAaAAUJJRRlNQDoAAAAAA==.Khari:BAAALgAECgEJAQAAAA==.Kheart:BAAALgAECgEJAQAAAA==.Kholy:BAAALgADCgYJBgAAAA==.',
Ki='Kidrash:BAAALgADCgcJCAAAAA==.Killah:BAAALgAECgQJBgAAAA==.Kimegh:BAAALgADCgIJAgAAAA==.Kitsunae:BAAALgADCgcJHgAAAA==.',
Kl='Kleredan:BAAALgAECgkJBgAAAA==.',
Ko='Koder:BAACLgAFFH8TAAIBAAYJfhqbHQB0AQABAAYJfhqbHQB0AQAuAAQKfzUABAEACQnsIbEGABIDAAEACQnsIbEGABIDABgABwlXGS8HANABAB0AAgkOArJEAEoAAAAA.Kozmoker:BAAALgAECgYJBgAAAA==.',
Kr='Krondys:BAAALgAECgYJBgAAAA==.Krytus:BAAALgAECgEJAgAAAA==.',
Ku='Kungpaochik:BAAALgAECgIJAwAAAA==.Kupó:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Ky='Kyakdeath:BAABLgAECn81AAMWAAgJUho3WgC4AQAWAAgJUho3WgC4AQAbAAEJKwlwPAAuAAAAAA==.',
Kz='Kzo:BAAALgAECgYJDQAAAA==.',
La='Lailyre:BAAALgADCgQJBAAAAA==.Larroy:BAAALgAECgEJAQAAAA==.',
Le='Lecker:BAAALgAECgEJAQAAAA==.Legado:BAAALgAECgUJBwAAAA==.',
Li='Lilbigcow:BAAALgAECgEJAwAAAA==.Lilithxander:BAAALgAECgUJCQAAAA==.Lilshooter:BAAALgAECgIJAwABLgAFFAQJBAACAAAAAA==.Lizzybordan:BAAALgAECgcJEwAAAA==.',
Ll='Llaaroyy:BAAALgADCgEJAQAAAA==.Llarroii:BAAALgAECgEJAgAAAA==.',
Lo='Lovar:BAAALgADCgYJBgAAAA==.',
Lu='Lucinick:BAABLgAECn8qAAMeAAgJRBXhCgCFAQAeAAYJ+BnhCgCFAQAfAAYJxQ20AQDDAAAAAA==.Lucy:BAAALgADCgIJAgAAAA==.Luxdiei:BAAALgAECgYJBgAAAA==.Luzziem:BAAALgAECgcJDwAAAA==.',
Ly='Lynx:BAAALgAECgEJBgAAAA==.',
Ma='Margause:BAAALgAECgIJAwAAAA==.Mariskama:BAABLgAECn8iAAIGAAkJ2gWScgBbAQAGAAkJ2gWScgBbAQAAAA==.Markusthered:BAAALgAECgMJBAAAAA==.Mazza:BAAALgAECgkJEQAAAA==.',
Mc='Mcbong:BAAALgAECgQJBwAAAA==.',
Me='Mello:BAAALgADCgYJBgAAAA==.Meowimabear:BAAALgADCgkJEAABLgAECgkJIwAFALYiAA==.Metal:BAAALgAECgQJDgAAAA==.Method:BAAALgADCgEJAQAAAA==.Meuccí:BAAALgAECgcJCwAAAA==.',
Mh='Mhelora:BAABLgAECn8VAAITAAYJ3wviawDxAAATAAYJ3wviawDxAAAAAA==.',
Mi='Mikkais:BAAALgAECgYJEQAAAA==.Mimacho:BAAALgAECgQJCAAAAA==.Minimini:BAACLgAFFH8VAAIHAAUJCxmMHgB8AQAHAAUJCxmMHgB8AQAuAAQKfy4AAgcACQkJHD4SAI0CAAcACQkJHD4SAI0CAAAA.Minni:BAAALgAFFAEJAwAAAA==.',
Mo='Moolin:BAABLgAECn8pAAIgAAkJigmmGwAvAQAgAAkJigmmGwAvAQAAAA==.Moranthe:BAAALgAECgcJDAABLgAFFAYJCwAHADsSAA==.Mordsyth:BAAALgAECgYJCgAAAA==.Morrowind:BAAALgADCgYJBgAAAA==.Mortis:BAAALgADCgYJBgAAAA==.',
Mu='Muggni:BAAALgAECgkJEQAAAA==.Muggypew:BAABLgAECn8UAAIhAAkJRgFlLgBeAAAhAAkJRgFlLgBeAAAAAA==.Munder:BAABLgAECn8mAAMiAAkJgB3UAwBxAgAiAAkJcBzUAwBxAgAJAAgJ/xkoUwCiAQAAAA==.Murdez:BAAALgADCgEJAQAAAA==.Mustymuppet:BAACLgAFFH8bAAIJAAUJmBciRwA6AQAJAAUJmBciRwA6AQAuAAQKfygAAwkACAnzGj83APwBAAkACAnzGj83APwBABUAAQlnD7VuADgAAAAA.',
My='Myrotheron:BAAALgADCgMJAwAAAA==.Mysticmeat:BAAALgAECgEJAQAAAA==.Mythicalbug:BAAALgADCgEJAQAAAA==.Mythuneran:BAABLgAECn8cAAIjAAkJdhe1AgAeAgAjAAkJdhe1AgAeAgAAAA==.',
['Mø']='Mørzanna:BAAALgAECgYJBwAAAA==.',
Na='Nanookigaluk:BAAALgADCgYJBgAAAA==.Narrator:BAAALgAECgEJAgAAAA==.Navikz:BAAALgADCgUJBQAAAA==.',
Ne='Nekrose:BAABLgAECn8aAAIWAAgJwiIeIACJAgAWAAgJwiIeIACJAgAAAA==.Nemini:BAABLgAECn8WAAMkAAYJjgtYPAADAQAkAAYJjgtYPAADAQAlAAEJ7AGtmgAcAAAAAA==.Nena:BAABLgAECn8nAAIRAAYJbBOJOwAjAQARAAYJbBOJOwAjAQAAAA==.Nenacurses:BAAALgAECgQJCAABLgAECgYJJwARAGwTAA==.Nephilia:BAAALgADCgYJBgAAAA==.Newfy:BAAALgAFFAEJAwAAAA==.',
Ni='Ninjamage:BAAALgAECgUJBQAAAA==.Nistis:BAAALgAECgYJEQAAAA==.Niteshroud:BAAALgADCgMJAwAAAA==.Nithendroz:BAABLgAECn8YAAMYAAcJZgoEFgC0AAAYAAQJZgsEFgC0AAABAAMJaAjngQBaAAAAAA==.Nity:BAAALgAECgQJBAAAAA==.Nivek:BAAALgAECgEJAQAAAA==.',
Nn='Nnivek:BAAALgAECgEJAQAAAA==.',
No='Noctaurus:BAABLgAECn8iAAIWAAkJ1QkaaQCUAQAWAAkJ1QkaaQCUAQAAAA==.Noczorro:BAAALgADCgYJBgAAAA==.Nomadhew:BAAALgAECgcJBwAAAA==.Noraice:BAAALgAECgEJAwAAAA==.Notagain:BAACLgAFFH8sAAILAAgJxhugBwBfAgALAAgJxhugBwBfAgAuAAQKfy4AAgsACQkBI5YHAFoDAAsACQkBI5YHAFoDAAAA.Notapally:BAAALgAECgQJBAAAAA==.Noxcorvus:BAAALgAECgcJDQAAAA==.',
Nu='Nuvo:BAAALgADCgYJBgAAAA==.',
Ny='Nylloc:BAAALgAECgkJCQAAAA==.Nymphàdoria:BAAALgAECgEJAQAAAA==.Nyuxx:BAABLgAECn8bAAIPAAgJaBMNOADPAQAPAAgJaBMNOADPAQAAAA==.',
['Nê']='Nêwfie:BAAALgAECgEJAwABLgAFFAEJAwACAAAAAA==.',
Oc='Oceanic:BAAALgADCgYJCwAAAA==.Oceans:BAAALgAECgEJAQAAAA==.',
Od='Odphijor:BAAALgAECgkJAQAAAA==.',
Ol='Olenza:BAAALgAECgQJBQAAAA==.Olgreeneyes:BAAALgAECgIJBAAAAA==.',
Or='Orangewhale:BAABLgAECn8UAAITAAYJChgpTABzAQATAAYJChgpTABzAQAAAA==.',
Ou='Out:BAAALgAECgYJCwAAAA==.',
Ox='Oxidation:BAAALgADCgcJGgAAAA==.',
Pa='Painspongie:BAAALgADCgQJBQAAAA==.Patsajak:BAAALgADCgEJAQAAAA==.Pavo:BAAALgAECgMJAwAAAA==.',
Pe='Pebbleshifts:BAAALgAECgMJAwAAAA==.Peejean:BAAALgAECgYJBgAAAA==.Peyblade:BAAALgAECgYJBgABLgAECgkJHgAUABghAA==.Peybreak:BAAALgAECgIJAgABLgAECgkJHgAUABghAA==.Peychi:BAAALgAECgUJBgABLgAECgkJHgAUABghAA==.Peycicle:BAABLgAECn8eAAIUAAkJGCFKAQDOAgAUAAkJGCFKAQDOAgAAAA==.Peysanity:BAAALgAECgQJBAABLgAECgkJHgAUABghAA==.Peystruction:BAAALgAECgEJAgABLgAECgkJHgAUABghAA==.Peytan:BAABLgAECn8VAAMOAAkJLxiHIwBCAgAOAAkJLxiHIwBCAgAaAAEJuQmmdgAuAAABLgAECgkJHgAUABghAA==.Peytin:BAAALgAECgQJBAABLgAECgkJHgAUABghAA==.',
Ph='Phantasm:BAAALgADCgQJBwAAAA==.Phemoid:BAAALgADCgkJCQAAAA==.',
Pi='Pinkywhale:BAAALgAFFAIJAgAAAA==.Pippa:BAABLgAECn8qAAIdAAkJ4xylBADeAgAdAAkJ4xylBADeAgAAAA==.Pitythefu:BAAALgADCgcJBQAAAA==.',
Pl='Planett:BAABLgAECn8lAAMPAAkJChyRFwCMAgAPAAkJChyRFwCMAgAcAAEJFgOQwQAcAAAAAA==.',
Po='Poetuck:BAABLgAECn8yAAIEAAkJnxQVTgDyAQAEAAkJnxQVTgDyAQAAAA==.Pokeyruler:BAAALgAECgIJAgAAAA==.Pokeythorn:BAAALgADCgkJFwAAAA==.Pookießear:BAAALgADCgUJBQAAAA==.Powdrpufgirl:BAAALgADCgMJAwABLgAECgYJCAACAAAAAA==.',
Pr='Proko:BAABLgAECn8qAAMcAAkJFxLEPgA5AQAcAAcJ2BLEPgA5AQAPAAQJLBWGcAAKAQAAAA==.',
Ps='Psychovoodoo:BAAALgAECgIJBwAAAA==.',
Pu='Publicpool:BAAALgADCgEJAQAAAA==.Purfec:BAAALgADCgcJDAAAAA==.',
Qa='Qatka:BAAALgAECgQJBQAAAA==.',
Qu='Quiver:BAABLgAECn8iAAILAAgJ1Q0thgBjAQALAAgJ1Q0thgBjAQAAAA==.Quizle:BAAALgAECgEJAwAAAA==.',
['Qì']='Qìlen:BAABLgAECn8WAAIXAAcJzgyxMgDRAAAXAAcJzgyxMgDRAAAAAA==.',
Ra='Raein:BAABLgAECn8rAAMPAAkJqyLuAwB9AwAPAAkJqyLuAwB9AwAcAAYJnBcOQwAnAQAAAA==.Raginghog:BAAALgAECgUJCAAAAA==.Rainn:BAACLgAFFH8KAAMNAAMJBhPTAwCiAAANAAMJBhPTAwCiAAALAAEJ6AE6ywA1AAAuAAQKfxcABA0ACAkGFdQbACUCAA0ACAkGFdQbACUCAAwABAmuBZ41AG4AAAsAAQlGBLLEASEAAAAA.Rainnsoul:BAAALgAECgYJDgAAAA==.Rakkclaw:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Ralofurius:BAAALgAECgYJCQAAAA==.Rasril:BAAALgAFFAEJAQAAAA==.Ratched:BAAALgADCgMJAwAAAA==.Raze:BAAALgAECgIJBgAAAA==.',
Re='Red:BAAALgADCgcJEgAAAA==.Redrighthand:BAAALgADCgEJAQAAAA==.Renicus:BAAALgADCgYJCAAAAA==.Renmare:BAABLgAECn8WAAIKAAUJOhfFVAD5AAAKAAUJOhfFVAD5AAAAAA==.Renmore:BAABLgAECn8VAAILAAgJMBEOdgCCAQALAAgJMBEOdgCCAQAAAA==.Rennzo:BAAALgADCggJDAAAAA==.Reshtargorr:BAAALgAECgEJAwAAAA==.Reze:BAAALgAECgEJAQAAAA==.',
Rg='Rgbpanda:BAAALgAECgQJBQAAAA==.',
Rh='Rhandoom:BAAALgADCgQJBAAAAA==.',
Ri='Ricky:BAAALgAECgEJAQAAAA==.Rikeji:BAAALgAECgYJCwAAAA==.Risotto:BAAALgAECgQJBwAAAA==.Riumi:BAAALgAECgMJCQAAAA==.Rivenxi:BAAALgAECgEJAQABLgAECgcJDAACAAAAAA==.',
Ro='Rocksolid:BAAALgAECgEJAgAAAA==.Ronaspreader:BAAALgAECgYJAwAAAA==.Roskolnikov:BAAALgAECgUJEAAAAA==.',
Ru='Rubymoonbeam:BAABLgAECn8mAAIGAAcJDw7HegBKAQAGAAcJDw7HegBKAQAAAA==.Ruele:BAACLgAFFH8LAAIHAAYJOxK9HQCCAQAHAAYJOxK9HQCCAQAuAAQKfxwAAgcACQnyH2sNAMUCAAcACQnyH2sNAMUCAAAA.Ruenan:BAABLgAECn8xAAMGAAkJxyaTAQB/AwAGAAkJxyaTAQB/AwAhAAMJlhKzaACcAAAAAA==.Ruma:BAAALgAECgQJBAAAAA==.',
Ry='Ryain:BAABLgAECn85AAMRAAkJtg+0LABzAQARAAkJ9Q20LABzAQASAAcJnw+lKgAIAQAAAA==.Ryian:BAAALgAECgQJBAAAAA==.',
['Rä']='Räinns:BAABLgAECn8YAAISAAcJNgo/GAD0AAASAAcJNgo/GAD0AAAAAA==.',
Sa='Saintstephen:BAAALgADCggJGQAAAA==.Santajr:BAABLgAECn8eAAImAAYJsAMbOgCMAAAmAAYJsAMbOgCMAAAAAA==.Sapthat:BAABLgAECn8bAAMnAAcJwyH7AwDqAQAnAAYJAyT7AwDqAQAeAAMJXBrkEQDnAAAAAA==.Sarahlina:BAAALgADCgcJBwAAAA==.Sarthrity:BAABLgAECn8aAAIEAAYJNwmc0QDvAAAEAAYJNwmc0QDvAAAAAA==.Satyrs:BAAALgAECgEJAQAAAA==.Savemeh:BAAALgAECgEJAQAAAA==.Savepebble:BAABLgAECn8fAAMJAAkJMxS7aABrAQAJAAgJ7Q+7aABrAQAVAAUJXxfKHgCzAAAAAA==.',
Sc='Scalesofdoom:BAAALgAECgEJAgAAAA==.',
Se='Seather:BAABLgAECn8cAAIfAAgJ4BvDEwB4AgAfAAgJ4BvDEwB4AgAAAA==.Seirin:BAABLgAECn8rAAIkAAkJbxMCFwAXAgAkAAkJbxMCFwAXAgAAAA==.Seldiane:BAAALgADCgUJBQAAAA==.Selendaa:BAAALgAECgUJEQAAAA==.Senadarra:BAACLgAFFH8cAAIhAAYJZhsVDgB+AQAhAAYJZhsVDgB+AQAuAAQKfzcAAiEACQkeIfICALECACEACQkeIfICALECAAAA.Sephenroth:BAAALgAECgQJBwAAAA==.Sephron:BAABLgAECn8YAAIoAAkJAhLtFQAqAgAoAAkJAhLtFQAqAgAAAA==.Serendipity:BAAALgAECgcJBwABLgAECggJFAAaALISAA==.Serqet:BAABLgAECn8mAAQOAAgJfxVhOwDaAQAOAAgJMBVhOwDaAQApAAUJaAQoJQB2AAAaAAIJuArYawA2AAAAAA==.Sethen:BAAALgAECgEJAQAAAA==.',
Sh='Shadowhawke:BAAALgADCggJCAAAAA==.Shadowofdoom:BAAALgAECgEJAQAAAA==.Shammology:BAABLgAECn8WAAIPAAcJPRJUTQB8AQAPAAcJPRJUTQB8AQAAAA==.Shaollyn:BAAALgAECgYJCQAAAA==.Sheri:BAABLgAECn8XAAIUAAkJPhzcAQBpAgAUAAkJPhzcAQBpAgAAAA==.Shizam:BAAALgAECgUJBQAAAA==.Shizzi:BAAALgAECgQJBgAAAA==.Shotowkhaan:BAABLgAECn8cAAMTAAcJFBRpRgB2AQATAAcJFBRpRgB2AQARAAEJaAIdqgAUAAAAAA==.Shotowkhann:BAAALgAECgIJAgAAAA==.Shoyoh:BAAALgAECgQJCQAAAA==.Shízu:BAAALgADCgkJDAAAAA==.',
Si='Sillygoose:BAACLgAFFH8mAAIEAAgJvRMDFwA8AgAEAAgJvRMDFwA8AgAuAAQKfyQAAgQACQlJIJEVACcDAAQACQlJIJEVACcDAAAA.Sinadara:BAAALgAECgYJEAAAAA==.Sinïster:BAAALgADCgEJAQABLgAECgYJDwACAAAAAA==.Siong:BAAALgADCgcJCgABLgAFFAgJJAALAAEhAA==.Siorknav:BAABLgAECn8fAAILAAgJiQ6FqQApAQALAAgJiQ6FqQApAQAAAA==.',
Sk='Skalar:BAABLgAECn8sAAIKAAgJ3A4WNAB6AQAKAAgJ3A4WNAB6AQAAAA==.Skipali:BAAALgAECgIJAwAAAA==.Skodah:BAAALgAECgEJAQABLgAECgYJDwACAAAAAA==.',
Sl='Släyr:BAAALgAECgMJBQAAAA==.',
So='Solunara:BAAALgADCgcJFgAAAA==.Somnambula:BAAALgADCgQJBAAAAA==.Sonadoria:BAABLgAECn8aAAIWAAgJ9w22dQB4AQAWAAgJ9w22dQB4AQAAAA==.Sorrenda:BAAALgADCgkJDwAAAA==.Soup:BAABLgAECn8nAAIgAAkJ/g3OEgCPAQAgAAkJ/g3OEgCPAQAAAA==.',
Sp='Sparow:BAAALgAECgEJAQAAAA==.Spinetarak:BAAALgADCgMJAwAAAA==.',
St='Stabbie:BAABLgAECn8XAAIfAAkJdRk7FQD2AQAfAAkJdRk7FQD2AQAAAA==.Stamina:BAAALgADCggJEAAAAA==.Stell:BAAALgAECgYJBwAAAA==.Stkawli:BAAALgAECgMJAwAAAA==.Stovik:BAACLgAFFH8HAAMDAAMJDxcaAQDZAAADAAMJDxcaAQDZAAAPAAEJTgoMgAA7AAAuAAQKfy4AAwMACQl1IRkEALYCAAMACQl1IRkEALYCAA8ABwnREddIAIsBAAAA.',
Sv='Sventhebrave:BAAALgAECgUJEgAAAA==.',
Sw='Sweeneytod:BAAALgAECgIJBwAAAA==.Sweetpally:BAAALgADCgUJCAAAAA==.',
Sy='Sykill:BAAALgAECgUJCQAAAA==.Sylira:BAACLgAFFH8PAAMkAAYJ5xGpDQBxAQAkAAYJ5xGpDQBxAQAoAAEJMAApVQARAAAuAAQKfzgAAyQACQmUIggIAOwCACQACQmUIggIAOwCACUAAwkWDoBmAIIAAAAA.Sylk:BAAALgAECgUJBQABLgAECgYJEAACAAAAAA==.',
['Sö']='Söl:BAAALgAECgQJBAAAAA==.',
Ta='Taintedfel:BAAALgADCgkJCAAAAA==.Takamura:BAAALgAECgcJBwAAAA==.Takedown:BAACLgAFFH8SAAIZAAUJdRyMAwANAQAZAAUJdRyMAwANAQAuAAQKfywAAxkACQlhJHwCACIDABkACQlhJHwCACIDAAoABwkrGsUsAAECAAAA.Talena:BAAALgAECgcJBwAAAA==.Talleral:BAABLgAECn8aAAMoAAkJfhbkDgCBAgAoAAkJfhbkDgCBAgAkAAEJ2BBNfwAzAAAAAA==.Tallyn:BAAALgAECgEJAQAAAA==.Tamanan:BAAALgAECgYJCwABLgAECgkJKwAoAM8OAA==.Tankie:BAAALgADCgEJAQAAAA==.Taurgrim:BAAALgADCgUJCQAAAA==.Tavin:BAAALgAECgEJAwAAAA==.Tazrav:BAAALgAECgMJAwAAAA==.',
Te='Temamañ:BAAALgAFFAIJAgAAAA==.Terasha:BAAALgAECgkJCQAAAA==.',
Th='Thalid:BAAALgADCgkJFQAAAA==.Tharonix:BAAALgAECgYJEwAAAA==.Thelitch:BAAALgADCgEJAgAAAA==.Theredpanda:BAAALgAECgUJBQAAAA==.Thewarden:BAAALgAECgIJAgAAAA==.',
Ti='Tic:BAAALgAECgYJBgAAAA==.Tigerwang:BAAALgAECgQJCAAAAA==.Tigrasia:BAAALgADCgYJCwAAAA==.Timaeus:BAACLgAFFH8GAAIEAAMJwg03gwDRAAAEAAMJwg03gwDRAAAuAAQKfzsAAgQACQlzHV0cALICAAQACQlzHV0cALICAAAA.Tinder:BAAALgADCgUJBQABLgAECgYJCAACAAAAAA==.',
Tm='Tmbeesknees:BAAALgAECgEJAQAAAA==.',
To='Touch:BAABLgAECn8VAAMlAAYJUQ0ERQD6AAAlAAYJUQ0ERQD6AAAoAAEJ/QlefwAtAAAAAA==.Touchofkarma:BAAALgADCgcJFAAAAA==.',
Tr='Trifflinhoes:BAAALgAECgUJEAAAAA==.Tristtan:BAAALgAECgEJAQAAAA==.Trôjan:BAAALgAECgQJAwAAAA==.',
Tu='Turningblue:BAAALgADCgUJBAAAAA==.Tusktilldawn:BAABLgAECn8VAAMXAAgJ5RB+GwCAAQAXAAgJzRB+GwCAAQAbAAIJ2wTnNgBBAAAAAA==.',
Tw='Twohoof:BAAALgADCgkJFQAAAA==.',
Ty='Tydrinor:BAAALgAECgcJAQAAAA==.',
['Tä']='Tänithðurden:BAAALgADCggJDgAAAA==.',
Ug='Ugin:BAAALgAECgUJBgAAAA==.',
Un='Unobasho:BAAALgAECgMJAwABLgAFFAQJCwABAH0PAA==.Unoboxo:BAAALgADCgEJAQABLgAFFAQJCwABAH0PAA==.Unovoke:BAACLgAFFH8LAAIBAAQJfQ8qNQDuAAABAAQJfQ8qNQDuAAAuAAQKfzUAAgEACQkrHUgSAFACAAEACQkrHUgSAFACAAAA.',
Va='Valeena:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Valorash:BAACLgAFFH8FAAILAAIJgBr7hwCjAAALAAIJgBr7hwCjAAAuAAQKfzsAAwsACQkIImIMAAIDAAsACQkIImIMAAIDAAwABgnKG7gPAMkBAAAA.Valorious:BAAALgAECgUJCAAAAA==.Vandaira:BAAALgAECgkJAQAAAA==.Vasillisa:BAAALgAECgMJBQAAAA==.',
Ve='Vearick:BAAALgADCgYJCgAAAA==.Veleyna:BAAALgADCgcJCwAAAA==.Velgryn:BAAALgAECgUJBAAAAA==.Velintha:BAAALgAECgcJCAAAAA==.Venatrix:BAAALgAECgYJEQAAAA==.Vendrith:BAAALgADCgcJBwAAAA==.Veraxi:BAAALgADCgYJCwABLgAECgUJCgACAAAAAA==.',
Vi='Vidascare:BAAALgAECgkJAgAAAA==.Vidu:BAAALgADCgUJBQAAAA==.Vision:BAAALgADCgYJBgAAAA==.',
Vl='Vluthier:BAAALgADCgYJBgAAAA==.',
Vo='Voidshatter:BAABLgAECn8bAAMaAAcJYgi5NgDgAAAaAAcJYgi5NgDgAAAOAAYJcQIM7gBhAAAAAA==.Vonderick:BAAALgAECgQJAwAAAA==.Voodoodog:BAAALgAECgMJBQABLgAECgYJDwACAAAAAA==.',
Vu='Vulgrimm:BAAALgAECgUJBQAAAA==.',
Vy='Vynlorellas:BAAALgAECgEJAgAAAA==.Vyéra:BAAALgADCgMJBgAAAA==.',
['Vè']='Vèsper:BAAALgAECgMJBQABLgAECgMJCQACAAAAAA==.',
Wa='Wakawli:BAAALgADCgYJBgAAAA==.Walex:BAAALgAECgkJBwAAAA==.Wally:BAAALgADCgMJAwAAAA==.Wardmneagle:BAAALgADCgUJCgAAAA==.Wargasm:BAAALgAECgQJBwABLgAECgcJEwACAAAAAA==.Watongo:BAAALgAECgUJBwAAAA==.Watsaheal:BAAALgAECgYJBwAAAA==.',
Wi='Wildborn:BAAALgADCgMJAwAAAA==.Willidan:BAAALgADCgEJAQAAAA==.Winwood:BAAALgADCgUJBwAAAA==.Withdrawals:BAAALgADCgYJBgABLgAECgMJCQACAAAAAA==.',
Wo='Woeify:BAABLgAECn8VAAIDAAcJ5xSuDgDRAQADAAcJ5xSuDgDRAQAAAA==.',
Wr='Wreckless:BAAALgAECggJCAABLgAFFAUJEgAeAFYeAA==.',
Wy='Wynce:BAAALgAECgUJCAAAAA==.',
Xa='Xalana:BAAALgADCgQJBAAAAA==.Xandaer:BAAALgAECgYJCAAAAA==.Xarn:BAABLgAECn8hAAIJAAkJtwdvagCOAQAJAAkJtwdvagCOAQAAAA==.',
Xc='Xcïte:BAABLgAECn8YAAQlAAgJwBo0JwCUAQAlAAYJ9hw0JwCUAQAkAAMJ3RtaWADUAAAoAAUJtxAZTQDQAAAAAA==.',
Xe='Xenroz:BAAALgADCgcJBwAAAA==.',
Ya='Yagudo:BAAALgADCgEJAQAAAA==.Yandòur:BAAALgADCgIJAgABLgAECgkJGQAVAIkPAA==.',
Ye='Yemon:BAAALgAECgUJBQAAAA==.',
Yo='Yodä:BAAALgADCgcJBwAAAA==.Yourlock:BAAALgADCgUJBQAAAA==.',
Yr='Yrelya:BAAALgAECgYJCQAAAA==.',
Yu='Yuji:BAACLgAFFH8LAAILAAMJjAjdfgC4AAALAAMJjAjdfgC4AAAuAAQKf04AAgsACQkZFqQyADYCAAsACQkZFqQyADYCAAAA.',
Za='Zalectra:BAACLgAFFH8UAAIFAAQJHiEqDABkAQAFAAQJHiEqDABkAQAuAAQKfz4AAwUACQm2JUIAAMUDAAUACQm2JUIAAMUDACEAAgmhFhoqAG0AAAAA.',
Ze='Ze:BAAALgAECgYJBwAAAA==.Zelila:BAAALgAECgUJBAAAAA==.Zephyruss:BAAALgADCgIJAgAAAA==.',
['Zü']='Zügzüg:BAAALgADCgEJAQAAAA==.',
['Âu']='Âurâ:BAAALgAECgUJBwAAAA==.',
['Ål']='Ålloria:BAABLgAECn8XAAIaAAgJExjwEwDzAQAaAAgJExjwEwDzAQAAAA==.',
['ßl']='ßlackßetty:BAAALgAECgMJBwAAAA==.',
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
