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

local lookup = {'Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Evoker-Devastation','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Marksmanship','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Frost','Warlock-Destruction','Druid-Restoration','Mage-Arcane','Mage-Frost','Shaman-Elemental','Priest-Holy','Priest-Discipline','Warrior-Protection','Monk-Mistweaver','Shaman-Enhancement','Evoker-Preservation','Paladin-Protection','Priest-Shadow','Druid-Balance','Druid-Guardian','Hunter-Survival','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='Blackrock',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Absolve:BAABNQAECoEZAAIBAAkJ+iB8BQBlAwABAAkJ+iB8BQBlAwAAAA==.',
Ad='Adamantium:BAAANQADCgQIBAABNQAECgkJJgACALskAA==.Adamantorc:BAABNQAECoEmAAICAAkJuyR/AQC4AwACAAkJuyR/AQC4AwAAAA==.Adampal:BAAANQAECgIIAgABNQAECgkJJgACALskAA==.Adowarlord:BAAANQADCgYIBwAAAA==.',
Ae='Aethylas:BAAANQAECgEIAQAAAA==.',
Af='Afsdruid:BAAANQADCgUIBQAAAA==.',
Ai='Aizzen:BAAANQAECgcIEAAAAA==.',
Ak='Akadeyjr:BAAANQADCggIEAAAAA==.Akaeus:BAAANQAECgIIAgAAAA==.Akhouel:BAAANQADCgQIBAAAAA==.',
Al='Albatross:BAAANQAECgIIAgAAAA==.Alfalfaflow:BAAANQADCggIEAAAAA==.Alienfreakdt:BAAANQAECgcIEQAAAA==.Allaon:BAAANQAECgcIDgAAAA==.Allerianna:BAAANQADCgIIAgAAAA==.Alyriel:BAAANQADCggIDQAAAA==.Alysun:BAAANQAECgQICAAAAA==.Alysyn:BAAANQAECgIIAgABNQAECgQICAADAAAAAA==.Alyys:BAAANQABCgIIAgABNQAECgQICAADAAAAAA==.Alèxander:BAAANQAECgEIAQAAAA==.',
Am='Amathel:BAAANQAECgQIBwAAAA==.Amynda:BAAANQADCgQIBAAAAA==.',
An='Angelsfìst:BAAANQAECgMIBgAAAA==.Annexin:BAAANQAECgUIBQABNQAECgYICgADAAAAAA==.',
Ap='Apocalyptic:BAAANQADCgEIAQAAAA==.',
Ar='Arawein:BAAANQAECgEIAQAAAA==.Aremis:BAAANQAECgUIDAABNQAECgkJGgAEAB4ZAA==.Argonius:BAAANQADCgUIBQAAAA==.Arka:BAAANQAECgEIAQAAAA==.Arkelly:BAAANQAECgYIEQAAAA==.Artemicion:BAAANQADCgIIAgABNQAECgQIBQADAAAAAA==.Arutoria:BAAANQADCggIEAAAAA==.',
As='Asche:BAAANQADCgYIBgAAAA==.Ashlie:BAAANQADCgYIBwAAAA==.Asirili:BAAANQAECgIIAwAAAA==.Asmoodeus:BAAANQAECggICgABNQAECgkJIQAFAN4jAA==.',
Au='Auramaxxer:BAAANQADCggICAAAAA==.',
Av='Avazen:BAAANQADCgQIBwAAAA==.',
Ay='Ayrah:BAAANQAECgIIAwAAAA==.',
Ba='Badaboom:BAAANQADCgcIBwAAAA==.Badeeasu:BAAANQADCgQIBAABNQAECgkJJgACALskAA==.Badshammy:BAAANQAECgEIAgAAAA==.Baelcoz:BAAANQAECgUICwAAAA==.Baragan:BAAANQADCggIDgAAAA==.',
Be='Bear:BAAANQAECgMIAwAAAA==.Bearwurst:BAAANQAECgQIBQAAAA==.Beazle:BAAANQAECgQIBQAAAA==.Beefchub:BAAANQAFFAEIAQAAAA==.Beladora:BAAANQAECgcIDwAAAA==.Bellarke:BAAANQADCgYIBgAAAA==.Belldelphine:BAABNQAECoEbAAQGAAkJ0ho4EQB7AgAGAAgJrRc4EQB7AgAHAAgJ9BoKEwBtAgAIAAIJVR9EDwCzAAAAAA==.',
Bi='Bichyone:BAAANQADCggIDwAAAA==.Bigback:BAAANQAECgYIEAAAAA==.Bigmeattréat:BAAANQAECgEIAQAAAA==.Bigpurr:BAAANQAECgUIBAABNQAECgkJGQAHANEaAA==.Bigtruss:BAAANQADCggICAAAAA==.Bilo:BAAANQAECgUICQAAAA==.Bimpo:BAAANQAECgEIAQAAAA==.',
Bl='Blangtron:BAAANQAECgYIDgAAAA==.Blickyz:BAAANQAECgMIBwAAAA==.Bloodbortie:BAAANQAECgUIBwAAAA==.Blödhgárm:BAAANQADCggICwABNQAECgcICwADAAAAAA==.',
Bo='Boatsnack:BAAANQADCgYIEAAAAA==.Boboko:BAAANQAECgQIBAAAAA==.Boderationx:BAAANQADCggIDwABNQAECgkJGwAJAGAkAA==.Bodyshots:BAAANQAECgcICAAAAA==.Boing:BAAANQABCgEIAQABNQADCgcIEwADAAAAAA==.Bokar:BAAANQADCgEIAQABNQAECggIFgAKANogAA==.Bolgc:BAAANQADCgcIBwABNQADCggIAwADAAAAAA==.Bonethug:BAAANQADCgUIBQAAAA==.Boofoo:BAAANQAECgMIAwAAAA==.Borbleybim:BAAANQAECgMIBQAAAA==.Borella:BAAANQADCgEIAQABNQAFFAUIDAALAEsYAA==.Bortikus:BAAANQADCgUIBwAAAA==.Boscho:BAAANQAECgcICAAAAA==.Boschoa:BAAANQAECgUICQABNQAECgcICAADAAAAAA==.Bouncedh:BAAANQAECgIIAwABNQAECgcIEQADAAAAAA==.Bowzarr:BAAANQADCgUICQAAAA==.Bowzerr:BAAANQADCgYIBgAAAA==.',
Br='Brayeda:BAAANQADCggIGwAAAA==.Breadpudn:BAAANQAECgUIBwAAAA==.Broccoliched:BAAANQADCggIFgAAAA==.Brodacz:BAAANQADCgYIEgAAAA==.Brownii:BAAANQAECgYICQAAAA==.',
Bu='Bubsdk:BAAANQABCgUIBQAAAA==.Burntbunss:BAAANQADCgUICQAAAA==.Burritortega:BAAANQADCggIIAAAAA==.',
['Bé']='Bérserkblave:BAAANQADCggIEAAAAA==.',
['Bó']='Bóunce:BAAANQAECgcIEQAAAA==.',
Ca='Cainos:BAAANQADCgQIBQAAAA==.Calandra:BAAANQAECgQICAAAAA==.Cantgetme:BAAANQAECgEIAQAAAA==.Carditis:BAABNQAECoEeAAICAAkJIB+RDAABAwACAAkJIB+RDAABAwAAAA==.Carditits:BAAANQADCgYIBgABNQAECgkJHgACACAfAA==.Catwilliams:BAAANQADCgYICAABNQAECgEIAQADAAAAAA==.',
Ce='Ceri:BAAANQADCggICAAAAA==.Cev:BAAANQAECgYICgABNQAECgkJIQALAAMmAA==.Cevren:BAABNQAECoEhAAMLAAkJAyanAAD0AwALAAkJAyanAAD0AwAMAAEJIxpyegBHAAAAAA==.',
Ch='Chaoselite:BAABNQAECoEcAAMNAAkJHRkuIACmAgANAAkJHRkuIACmAgABAAcJnwmoRwCQAQAAAA==.Chelia:BAAANQAECgEIAQAAAA==.Chuibacca:BAAANQAECgUICAAAAA==.',
Cl='Claanx:BAAANQAECgIIAQAAAA==.Clops:BAAANQADCgUICwAAAA==.',
Co='Cobrakilla:BAAANQAECgIIAgAAAA==.Cobrakiller:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.Coldgrasp:BAAANQADCgcIBwAAAA==.Coochpooch:BAAANQADCgYIDAAAAA==.Corbun:BAAANQADCgYIEwAAAA==.Corpsebane:BAAANQAECgQIBAAAAA==.Cortèx:BAAANQADCgEIAQAAAA==.Cosmicgate:BAABNQAECoEYAAIHAAgJziEVCAAhAwAHAAgJziEVCAAhAwAAAA==.Cowlawladin:BAAANQAECgQIBgAAAA==.',
Cr='Crockett:BAABNQAECoEYAAIOAAgJLBKXOQASAgAOAAgJLBKXOQASAgAAAA==.Croissantz:BAAANQAECgUIDQAAAA==.Crusha:BAAANQADCgMIAwAAAA==.Cryssis:BAAANQADCgYIBgAAAA==.',
Cu='Cubanmage:BAAANQAECgQICAAAAA==.Cubanpally:BAAANQAECgIIAgABNQAECgQICAADAAAAAA==.Cucucachoo:BAAANQADCggIFAAAAA==.',
Cy='Cyndi:BAAANQADCgYIDgAAAA==.Cynnabar:BAAANQADCgIIAgAAAA==.Cyrce:BAAANQADCgQIBAAAAA==.',
Da='Daanos:BAAANQADCgYIBgABNQAECgcIEAADAAAAAA==.Daeltha:BAABNQAECoEaAAIEAAkJHhkDBgDdAgAEAAkJHhkDBgDdAgAAAA==.Dafdafdaf:BAAANQAECgQIBAAAAA==.Daffenprime:BAABNQAECoEcAAIPAAkJTR40BgAUAwAPAAkJTR40BgAUAwAAAA==.Dailong:BAAANQAECgIIAgAAAA==.Dalux:BAAANQADCgUIBgAAAA==.Danastey:BAAANQADCgYIBgAAAA==.Daneglesack:BAAANQAECgUICAAAAA==.Danoslock:BAAANQADCggICAABNQAECgcIEAADAAAAAA==.Danosxd:BAAANQAECgcIEAAAAA==.Daragnos:BAABNQAECoEZAAMFAAgJRB74IABqAgAFAAcJmh74IABqAgAQAAQJSRW6JgAGAQAAAA==.Darkhært:BAAANQAECgUICwAAAA==.Darkkai:BAAANQAECgcIEQAAAA==.Darthmuffin:BAAANQAECggIDQAAAA==.Daryl:BAAANQAFFAEIAQABNQAFFAIIAQADAAAAAA==.Dasprime:BAAANQAECgQIBAAAAA==.Dastòmper:BAAANQADCgUIBQABNQAECgMIBAADAAAAAA==.Dayven:BAAANQADCgEIAQAAAA==.',
De='Deadhitmann:BAAANQAECgEIAQAAAA==.Deathbringer:BAAANQAECgYIBQAAAA==.Deathpenance:BAAANQADCgYIBgAAAA==.Deathãngel:BAAANQAECgYICwAAAA==.Decall:BAEANQAECgMIBgAAAA==.Decepper:BAAANQAECgEIAQAAAA==.Degraded:BAAANQAECggIDQAAAA==.Delenix:BAAANQADCgYIBgABNQADCggIDQADAAAAAA==.Demelion:BAAANQAECgMIAwABNQAECgkJFwACAOgbAA==.Demonblood:BAAANQAECgEIAQAAAA==.Ders:BAAANQADCggIDgAAAA==.Dessius:BAAANQAECgYIBAAAAA==.Dethstra:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.Deüs:BAAANQAECgQICAAAAA==.',
Di='Diffstyle:BAAANQAECggICQAAAA==.Dionotus:BAAANQADCgcIFAAAAA==.Dirtgrub:BAAANQAECgIIAgAAAA==.Divdan:BAAANQADCggICAAAAA==.Divert:BAAANQADCggICAAAAA==.',
Dk='Dkhaoz:BAAANQAECgcIDgABNQADCgYIDAADAAAAAA==.Dkinabox:BAAANQADCggIAgABNQAECgEIAQADAAAAAA==.',
Do='Docturnal:BAAANQADCgMIAwAAAA==.Dolphina:BAAANQAECgQIBAAAAA==.Donfrancisco:BAAANQAECgEIAQAAAA==.Donsaul:BAAANQADCggICgAAAA==.Donuts:BAAANQADCgMIAwAAAA==.Doomsure:BAAANQADCgMIAwAAAA==.Doryani:BAAANQAECgQIBAAAAA==.Doømhammer:BAAANQADCggICAAAAA==.',
Dr='Dracburton:BAAANQADCgEIAQAAAA==.Drachen:BAAANQADCgYIBgABNQAECgcICAADAAAAAA==.Dracnaphobia:BAAANQADCgMIAwABNQAECgQIBgADAAAAAA==.Dragynsabor:BAAANQADCgUICQAAAA==.Dragynsoul:BAAANQADCgYIDAAAAA==.Dranok:BAAANQADCgYIDQAAAA==.Dratnosfan:BAAANQADCgYICgABNQAECgcIEAADAAAAAA==.Drballseks:BAAANQAECgQIBAAAAA==.Dreadfox:BAAANQADCgYIBgAAAA==.Dreamlike:BAABNQAECoEdAAIRAAkJdCE5AwBIAwARAAkJdCE5AwBIAwAAAA==.Drezco:BAAANQADCgUIBwABNQAECgkJIQALAAMmAA==.Droit:BAAANQAECgQIBAAAAA==.Drstormii:BAAANQAECgEIAQAAAA==.Drumelion:BAAANQAECgUIBwABNQAECgkJFwACAOgbAA==.',
Du='Dukazra:BAAANQADCgcIHAAAAA==.Dunkndonuts:BAAANQAECgUICQAAAA==.',
['Dé']='Déathy:BAAANQAECgIIAgABNQAECgQIBAADAAAAAA==.',
Ea='Earthencore:BAAANQAECgUIDgAAAA==.',
Ed='Edgyboy:BAAANQAECgEIAQAAAA==.Edjelord:BAAANQADCgcICQAAAA==.',
Eg='Eggmilk:BAAANQADCgUIBQAAAA==.Egirltank:BAAANQADCgcIDQABNQAECgcIEgADAAAAAA==.',
El='Elaxa:BAAANQADCggICAABNQAECgkJHwAHAIwjAA==.Eldanath:BAAANQADCgYIBgAAAA==.Elnaa:BAAANQADCgUIBQAAAA==.Elsulan:BAAANQADCggICAAAAA==.Elteethree:BAAANQAECgYIEQABNQAFFAUIBwACAEMZAA==.Elunelock:BAAANQADCggIEAAAAA==.Elunepal:BAAANQAECgQIBgAAAA==.Elys:BAAANQAECgUIBgAAAA==.',
Em='Emalynn:BAAANQADCgYIBgAAAA==.Emilyfrost:BAAANQADCgQIBAAAAA==.',
En='Enigmà:BAABNQAECoEcAAMSAAgJcBHibAAAAgASAAgJcBHibAAAAgATAAEJ4AG1LAAqAAAAAA==.Enmanuel:BAAANQAECgYICQAAAA==.',
Ep='Epyôn:BAABNQAECoEdAAIUAAkJnSB1CgBKAwAUAAkJnSB1CgBKAwAAAA==.',
Er='Ericthebrave:BAAANQADCgYIBgAAAA==.Eriodara:BAAANQADCgIIAgAAAA==.',
Es='Escas:BAAANQAECgUICgAAAA==.Escaz:BAAANQAECgQIBAAAAA==.Esrahaddon:BAAANQAECgUIDgAAAA==.',
Ev='Evanora:BAAANQAECgQICAAAAA==.Evillinx:BAAANQAECgIIAwAAAA==.Evilmaru:BAAANQAECgEIAQAAAA==.Evokelion:BAAANQAECgMIAwABNQAECgkJFwACAOgbAA==.',
Ew='Ewok:BAAANQADCgQIBAAAAA==.',
Ex='Exploited:BAAANQADCgcIBwAAAA==.',
Fa='Factz:BAAANQADCgEIAQAAAA==.Faespalmn:BAABNQAECoEYAAICAAgJDSAYEgDJAgACAAgJDSAYEgDJAgAAAA==.Fatalstab:BAAANQAECgMIAwAAAA==.Fauin:BAAANQADCgYIBgAAAA==.',
Fe='Featheramby:BAAANQADCgEIAQAAAA==.Felenesh:BAAANQADCgEIAQAAAA==.Fenthead:BAAANQADCgYICgABNQAECgcIEgADAAAAAA==.Fernandôge:BAAANQAECgUIDAAAAA==.',
Fi='Fidel:BAAANQAECgYIDAAAAA==.Fil:BAAANQAECgcIDAAAAA==.Fisac:BAACNQAFFIEHAAIJAAUJqBI4AwCZAQAJAAUJqBI4AwCZAQA1AAQKgSAAAgkACQlzIOwFADsDAAkACQlzIOwFADsDAAAA.Fishbubble:BAAANQABCgYIBwAAAA==.Fistbox:BAAANQADCggICAAAAA==.',
Fl='Fletchtern:BAAANQADCgEIAQABNQAECgQICQADAAAAAA==.Flexicute:BAAANQADCgcIBwAAAA==.Flexlock:BAAANQADCgMIAwAAAA==.Flextime:BAAANQAECgQIBwAAAA==.Flippinfear:BAAANQAECgYIBgAAAA==.',
Fo='Folius:BAACNQAFFIEOAAMFAAYJVh7SAAD1AQAFAAUJ+iDSAAD1AQAQAAEJIhGbCgBbAAA1AAQKgRwAAwUACQlYJr4AANUDAAUACQlYJr4AANUDABAAAwn7Ha8pAPMAAAAA.Fortyourself:BAAANQADCggIDwABNQAECgkJHgACACAfAA==.',
Fr='Franky:BAAANQAECgYICgAAAA==.Franzu:BAAANQAECgcIDQAAAA==.Freehits:BAAANQADCgEIAQAAAA==.Freelaughs:BAAANQADCgQIBAAAAA==.Friggitte:BAAANQADCgcIEwAAAA==.Friholy:BAAANQAECgQICAABNQAECggIFgACAG8UAA==.Frostdragyn:BAAANQADCgYICwAAAA==.Frosteviã:BAAANQAECgQIBAAAAA==.',
Fu='Full:BAAANQADCggIFAAAAA==.Furgoblin:BAAANQAECgQIBAABNQAECgUICwADAAAAAA==.',
['Fâ']='Fâdêd:BAAANQADCggICAAAAA==.',
['Fä']='Fäerise:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëanör:BAAANQAECgQIDAAAAA==.',
['Fø']='Førce:BAAANQAECgEIAQAAAA==.',
Ga='Gabi:BAAANQADCgcIDQAAAA==.Gacrüx:BAAANQADCggIFwAAAA==.Galadrìel:BAABNQAECoEbAAINAAkJqxeSIwCQAgANAAkJqxeSIwCQAgAAAA==.Galadrìèl:BAAANQAECgEIAQAAAA==.Gambol:BAAANQADCgYIBgAAAA==.Garegar:BAAANQADCgYIBgAAAA==.',
Ge='Gengizkhan:BAAANQADCgQIBQABNQADCgYICgADAAAAAA==.',
Gh='Ghorn:BAAANQAECgQIBQAAAA==.',
Gl='Glaivetoes:BAAANQAECgMIAwAAAA==.Glareaforsor:BAAANQADCggICgAAAA==.Glimpse:BAAANQAECgMIBAAAAA==.Glytteris:BAAANQAECgMIAwAAAA==.',
Go='Gochurass:BAAANQAECgEIAQAAAA==.Goonspree:BAAANQADCgEIAQAAAA==.',
Gr='Grabbyhands:BAAANQADCgEIAQAAAA==.Grapthar:BAEANQADCggIEwABNQAECgMIBgADAAAAAA==.Grenth:BAAANQADCgMIAwAAAA==.Greyarrow:BAAANQAECgMIBgAAAA==.Greæd:BAACNQAFFIELAAIVAAYJvRZgAQARAgAVAAYJvRZgAQARAgA1AAQKgSEAAxUACQloJOQEAFYDABUACQloJOQEAFYDABYABgnLHWUGAKYBAAAA.Grimgown:BAAANQAECgMIAwABNQAECgYICgADAAAAAA==.Grimreaper:BAAANQADCggIEQABNQAECgMIBAADAAAAAA==.Grizzard:BAAANQAECgIIAwAAAA==.Gruckek:BAABNQAECoEZAAMKAAgJsRjVOQBRAgAKAAgJLhjVOQBRAgAXAAIJTg1DHgBiAAAAAA==.Grææd:BAAANQAECgQIBAABNQAFFAYICwAVAL0WAA==.',
Gu='Gulanis:BAAANQAECgQIBQAAAA==.Guldhakii:BAAANQAECgcIBwAAAA==.',
Gw='Gwendlyne:BAAANQAECgIIAwAAAA==.',
['Gó']='Góddess:BAAANQADCggICQAAAA==.',
Ha='Hag:BAAANQAECgQIBAABNQAFFAYICAANAMkNAA==.Hakarii:BAAANQAECgIIAgABNQAECgkJGQAHANEaAA==.Halloffaith:BAAANQAECgcIDwAAAA==.Harissa:BAAANQADCgEIAQABNQAECgQIBAADAAAAAA==.Harry:BAAANQADCggICAAAAA==.Hawgneto:BAAANQADCggIDQAAAA==.Hazel:BAAANQAECgQIBAAAAA==.',
He='Hellig:BAAANQAECgcIEAAAAA==.Hellofriday:BAAANQADCggICAAAAA==.Hellíg:BAAANQADCggIDgAAAA==.Hetzfury:BAAANQADCgEIAQAAAA==.Heyman:BAAANQADCggIGgAAAA==.',
Hi='Hideyerweed:BAAANQADCgQIBAABNQAECgcIEwADAAAAAA==.Higi:BAAANQADCgYIBgAAAA==.',
Ho='Holistic:BAABNQAECoEVAAICAAgJuCXsBABpAwACAAgJuCXsBABpAwAAAA==.Holyclanx:BAAANQADCgYIBgAAAA==.Holylips:BAAANQAECggIAQAAAA==.Holyzamboni:BAAANQAECggIDwAAAA==.Honeyblunt:BAAANQADCgIIAgAAAA==.Hotchocmilk:BAAANQAECgQICAAAAA==.',
Hr='Hr:BAAANQADCgcIBwAAAA==.',
Hu='Hunex:BAAANQADCgIIAgAAAA==.Huntaa:BAAANQAECgcIEgAAAA==.Hurají:BAABNQAECoEXAAMBAAkJ7xjMEADdAgABAAkJ7xjMEADdAgANAAUJuQK/sgCdAAABNQAFFAUICQAYAOoXAA==.Huråji:BAACNQAFFIEJAAIYAAUJ6hezAADUAQAYAAUJ6hezAADUAQA1AAQKgRwAAhgACQkIIcMCAEQDABgACQkIIcMCAEQDAAAA.',
Il='Ilnookll:BAAANQADCgUICQAAAA==.',
Im='Imblooms:BAAANQADCgEIAQAAAA==.Imbooms:BAAANQADCgYIBgAAAA==.Imryl:BAAANQAECgYIDAAAAA==.',
Io='Ionea:BAAANQADCgYIBgABNQAECgYIDgADAAAAAA==.',
Ir='Ironpaws:BAAANQAECgUICwAAAA==.Iryssoscaly:BAAANQADCgIIAgAAAA==.',
Is='Isa:BAAANQAECgYICwABNQAECgkJGQAHANEaAA==.Isaa:BAABNQAECoEZAAMHAAkJ0RplDQDDAgAHAAkJuRplDQDDAgAGAAIJlhcjPwCZAAAAAA==.Istredd:BAAANQAECgEIAQAAAA==.',
It='Itamedruids:BAAANQADCggIDgABNQAECgEIAQADAAAAAA==.',
Ja='Jackrackham:BAAANQAECgQICAAAAA==.Jakuza:BAAANQADCgYIBgABNQAECgQIBwADAAAAAA==.Jaydeep:BAAANQABCgIIAgAAAA==.Jayrayco:BAAANQABCgQIBQAAAA==.',
Jd='Jdub:BAAANQAECgYICAAAAA==.',
Je='Jebx:BAAANQADCgYIBgABNQAFFAMIBQAUAH0WAA==.Jebydk:BAAANQADCggIGQABNQAFFAMIBQAUAH0WAA==.Jebysham:BAACNQAFFIEFAAIUAAMJfRbkBQALAQAUAAMJfRbkBQALAQA1AAQKgSAABBQACQmOH+YPAAgDABQACQnGHuYPAAgDABkABwlOHA4IAHACAAIAAglEAg2oAE4AAAAA.Jeffybubbles:BAAANQADCggIEAAAAA==.Jeffytotems:BAAANQAECgcIDgAAAA==.Jelsy:BAAANQAECgMIBgAAAA==.Jepx:BAAANQAECgQIBQAAAA==.Jesly:BAAANQADCgUIDAABNQAECgMIBgADAAAAAA==.Jessibella:BAABNQAECoEgAAIVAAkJfRl8FgCRAgAVAAkJfRl8FgCRAgAAAA==.',
Jh='Jhnstzy:BAAANQADCgYICwAAAA==.',
Ji='Jimmyhoofa:BAAANQABCgEIAQABNQADCgcIEwADAAAAAA==.',
Jo='Johnsteez:BAAANQAECgEIAQAAAA==.Jorndalf:BAAANQAECgcIDwAAAA==.',
Jt='Jt:BAAANQABCgIIAgAAAA==.',
Ju='Juggz:BAAANQAECgQICQAAAA==.Justabutcher:BAAANQAECgQICwAAAA==.',
Jw='Jwag:BAAANQADCgYIDQAAAA==.',
['Jê']='Jêcht:BAABNQAECoEfAAIVAAkJpSPCBQBHAwAVAAkJpSPCBQBHAwAAAA==.',
Ka='Kafur:BAAANQAECgUICQAAAA==.Kaiido:BAAANQAECgEIAgABNQAECgkJGQAHANEaAA==.Kakesoba:BAAANQADCgcIBwABNQADCgYIEAADAAAAAA==.Karmanda:BAAANQADCgcIEgAAAA==.Kattel:BAAANQADCggIDAAAAA==.Kaychow:BAAANQAECgYIBgAAAA==.',
Ke='Keither:BAAANQADCgMIAwABNQADCgcIEwADAAAAAA==.Kelendor:BAABNQAECoEdAAIOAAkJqw9gIwB4AgAOAAkJqw9gIwB4AgAAAA==.Kellandil:BAAANQADCgQICQAAAA==.Kenju:BAAANQAECgUICAAAAA==.Kensie:BAAANQAECgcIDAAAAA==.',
Kh='Khlampz:BAAANQAECgcIDgAAAA==.Khlampzight:BAAANQAECgUICAABNQAECgcIDgADAAAAAA==.Khlampzoker:BAAANQADCggIEAABNQAECgcIDgADAAAAAA==.Khondor:BAAANQADCgIIAwAAAA==.',
Ki='Kiel:BAAANQAECgQIBQAAAA==.Kigen:BAAANQAECgEIAQAAAA==.Kikurface:BAAANQADCggIGAAAAA==.Kimjungun:BAAANQADCgEIAQAAAA==.Kiranax:BAABNQAECoEmAAQLAAkJ9CRhAQDYAwALAAkJ9CRhAQDYAwAMAAMJVAc0agCDAAAPAAEJ1RJNUQAyAAAAAA==.Kiraxxus:BAAANQAECgYIBgABNQAECgkJJgALAPQkAA==.Kittensune:BAAANQABCgYIBgAAAA==.',
Ko='Koinu:BAABNQAECoEcAAIYAAgJdiEfBAANAwAYAAgJdiEfBAANAwAAAA==.Kooriaisu:BAAANQADCgUIBQAAAA==.Korbun:BAAANQADCgYICAAAAA==.Kovskii:BAAANQADCggIHAAAAA==.',
Kr='Krad:BAAANQADCggIEwAAAA==.Kriathura:BAAANQAECgYICgAAAA==.',
Ku='Kukui:BAAANQADCgYIBgABNQAECgQICAADAAAAAA==.',
Kw='Kwangpow:BAAANQAECgIIBAAAAA==.',
['Kà']='Kàkàshi:BAAANQAECgYIEAAAAA==.',
La='Laethal:BAAANQADCgQIBQAAAA==.Lambbchopp:BAAANQADCgUIDgAAAA==.Lassitar:BAAANQADCgEIAQAAAA==.Lazyrage:BAAANQAECgQIBAAAAA==.Lazyreaper:BAAANQADCgUICwABNQAECgQIBAADAAAAAA==.',
Le='Lebronto:BAABNQAECoEWAAIKAAgJ2iBUHADtAgAKAAgJ2iBUHADtAgAAAA==.Legsquats:BAAANQAECgQIBAABNQAFFAEIAQADAAAAAA==.Lessirs:BAAANQADCggIFwAAAA==.Lexatron:BAAANQABCgEIAQAAAA==.',
Li='Lichnaught:BAAANQADCgUIDAABNQAECgMIBgADAAAAAA==.Lifetapped:BAAANQADCggIGAAAAA==.Lilfluffy:BAAANQAECgIIAgAAAA==.Liquid:BAAANQADCgcIEAAAAA==.Little:BAAANQABCgQIBAAAAA==.',
Ll='Llikdaor:BAAANQAECgQICgAAAA==.',
Lo='Loaded:BAAANQAECgYIDgAAAA==.Lockitupp:BAAANQADCgUIBQAAAA==.Loikk:BAAANQADCgMIAwAAAA==.Loodacrits:BAAANQAECgUIBwAAAA==.',
Lu='Lushylock:BAAANQADCgEIAQAAAA==.',
Ma='Macklin:BAAANQAECgEIAQAAAA==.Maddalynn:BAAANQAECgcIEAAAAA==.Maelstrox:BAAANQADCgUIDQAAAA==.Magandadrake:BAABNQAECoEcAAIaAAkJGhFuDgA+AgAaAAkJGhFuDgA+AgAAAA==.Magerita:BAAANQADCgQIBAAAAA==.Magharat:BAAANQADCgYIDwABNQAECgkJGgAUABcjAA==.Magicman:BAAANQADCgYIBgAAAA==.Malacanthet:BAAANQADCggIEAAAAA==.Mandelstam:BAAANQAECgQIBgAAAA==.Mangkanor:BAAANQADCgYICgAAAA==.Mangoloidman:BAAANQADCgIIAgABNQADCggICgADAAAAAA==.Marow:BAAANQADCgQIBAAAAA==.Marsan:BAAANQABCgQIBgAAAA==.Marxen:BAAANQADCgQIBAAAAA==.',
Mc='Mcsstab:BAAANQADCgYIBgAAAA==.',
Me='Meatballer:BAAANQAECgEIAQAAAA==.Meatballz:BAAANQAECgYIDgAAAA==.Mecalux:BAAANQAECgEIAQAAAA==.Meliodäs:BAAANQADCgYIBgABNQADCgYICQADAAAAAA==.Meloco:BAAANQAECgIIAgAAAA==.Melody:BAACNQAFFIELAAIVAAYJix6sAABHAgAVAAYJix6sAABHAgA1AAQKgR0AAhUACQkaJoQCAIsDABUACQkaJoQCAIsDAAAA.Menj:BAAANQADCgUIBwABNQAECgUICAADAAAAAA==.Meno:BAAANQADCggIDwAAAA==.Meowcheese:BAAANQAECgQIBQAAAA==.Meowmix:BAAANQADCgUIBQABNQAECgQIBAADAAAAAA==.Meridah:BAAANQADCgUIBQAAAA==.Mert:BAAANQADCgMIAwAAAA==.Mesosphere:BAEANQAECgQIBQAAAA==.',
Mi='Midorii:BAAANQAECgEIAQAAAA==.Migpala:BAAANQAECgIIAgAAAA==.Miiniimaage:BAAANQAECgIIBAAAAA==.Milkmann:BAAANQABCgIIAgAAAA==.Milkymoos:BAAANQAECgQICAAAAA==.Minar:BAAANQAECgYIDwABNQAECgcIEwADAAAAAA==.Minoic:BAAANQADCgYIFAAAAA==.Mistamiyagi:BAAANQAECgUIBgAAAA==.Mistchivus:BAAANQAECgQIBAAAAA==.Mistelion:BAAANQAECgQIBAABNQAECgkJFwACAOgbAA==.',
Mk='Mkultra:BAAANQADCgcIBwAAAA==.',
Mo='Mobbster:BAAANQADCggIGgAAAA==.Mohnster:BAAANQADCgMIBAAAAA==.Moisttotems:BAAANQADCgEIAQAAAA==.Monipouch:BAAANQAECgYICwAAAA==.Moonchicken:BAAANQADCgQIBAAAAA==.Moondaisy:BAAANQADCgIIAgAAAA==.Moopocalypse:BAAANQAECgQIBAAAAA==.Moosenukle:BAAANQADCgQIBQAAAA==.Morphaeus:BAAANQADCgUICgAAAA==.Mortar:BAAANQAECgMIAwAAAA==.Mozrog:BAAANQAECgcIDQAAAA==.',
Ms='Mshchase:BAAANQADCgEIAQAAAA==.',
Mu='Muffblaster:BAABNQAECoEbAAISAAkJvSDXEgBYAwASAAkJvSDXEgBYAwAAAA==.Murphet:BAAANQAECgQIBgAAAA==.',
My='Mythrix:BAAANQAECgUIBwAAAA==.',
['Mí']='Míra:BAAANQAECgMIAwAAAA==.',
['Mó']='Mónsoon:BAAANQABCgUIBQAAAA==.',
['Mö']='Mönïca:BAAANQAECgMIBAAAAA==.Mörrys:BAAANQAECgIIAgAAAA==.',
Na='Narrath:BAAANQABCgYICAAAAA==.Narwhal:BAAANQAECgIIAgAAAA==.Nathenatra:BAAANQADCgQIBAABNQAECgkJHAAPAE0eAA==.',
Ne='Neeko:BAAANQAECgYIDAAAAA==.Nenechi:BAAANQAECgEIAQABNQAFFAIIAQADAAAAAA==.Neonmoose:BAAANQAECgIIAgAAAA==.Nezbrez:BAAANQADCgcIDQAAAA==.Nezzrad:BAAANQADCgMIAwAAAA==.',
Nh='Nhthree:BAAANQAECgQICgAAAA==.',
Ni='Niklaws:BAAANQAECgEIAQABNQAECggIFgACAG8UAA==.',
No='Nofsha:BAAANQADCgUIBQABNQAECgUIBwADAAAAAA==.Noktyx:BAAANQADCggICAAAAA==.Nomoney:BAAANQAECgEIAwAAAA==.Norasong:BAAANQADCggIGAAAAA==.Norava:BAAANQAECgMIAwAAAA==.Nostick:BAABNQAECoEbAAMHAAkJdiGIBQBWAwAHAAkJdiGIBQBWAwAGAAIJmR4OQgCFAAAAAA==.Novacrono:BAABNQAECoEZAAIEAAkJZQ3QCwAwAgAEAAkJZQ3QCwAwAgAAAA==.Nozdog:BAAANQADCgUICQAAAA==.',
Nu='Nuke:BAABNQAECoEiAAIKAAgJgxT2PQA+AgAKAAgJgxT2PQA+AgAAAA==.',
['Nô']='Nôôk:BAAANQAECgMIBAAAAA==.',
Oa='Oaklánd:BAAANQAECggIAQAAAA==.',
Od='Odeinn:BAAANQADCgEIAQAAAA==.Odiare:BAAANQADCgUIBQAAAA==.',
Ok='Okogo:BAAANQADCgQIBAABNQADCgYICgADAAAAAA==.',
Op='Opta:BAAANQADCggIDgAAAA==.',
Or='Orkhis:BAAANQAECgYICgAAAA==.',
Ou='Outbrèak:BAAANQAECgQIBwAAAA==.',
Ow='Owo:BAAANQABCgQIBQABNQAECgQICAADAAAAAA==.',
Oz='Ozzyosbourne:BAAANQABCggIDQAAAA==.',
['Oá']='Oáklánd:BAAANQAECggICAAAAA==.',
Pa='Pakuru:BAAANQAECgcIEAAAAA==.Pal:BAAANQAECgIIAgAAAA==.Palachin:BAAANQAECgcIDQAAAA==.Paladelion:BAABNQAECoEWAAMBAAkJ2hi6HAB9AgABAAgJrRe6HAB9AgANAAUJMBq6YgB1AQABNQAECgkJFwACAOgbAA==.Paleonebula:BAAANQADCgYIBgAAAA==.Pallmtree:BAAANQAECgMIBAABNQAECgYICgADAAAAAA==.Pallyberry:BAAANQADCgYIBgABNQAECgQIBQADAAAAAA==.Pangittroll:BAAANQAECgUICQAAAA==.Papatotems:BAAANQADCgcICgAAAA==.Papå:BAAANQAECgQIBQAAAA==.Pawtirra:BAAANQADCgIIAgAAAA==.',
Pe='Perfume:BAAANQAECgEIAQAAAA==.Persephone:BAAANQADCgMIAwABNQAECgcIEwADAAAAAA==.Petri:BAAANQAECgQIBwAAAA==.',
Pi='Pickwaton:BAAANQAECggIEwAAAA==.Pipen:BAACNQAFFIEKAAIBAAQJcQc5BQAtAQABAAQJcQc5BQAtAQA1AAQKgSIAAw0ACQl+Gi8yAD0CAA0ACAkTGS8yAD0CAAEACQlUC/koAC0CAAAA.Pixelglitter:BAAANQADCgYIBgAAAA==.',
Pl='Pld:BAAANQADCgcIBwAAAA==.',
Po='Potatatoes:BAAANQADCgUIBQAAAA==.Poxrot:BAAANQADCgQIBAABNQADCgcIFQADAAAAAA==.',
Pr='Praize:BAABNQAECoEdAAMFAAkJtBqJHgB4AgAFAAgJ8xmJHgB4AgAQAAQJcRSLIwAdAQAAAA==.Press:BAACNQAFFIEIAAINAAYJyQ0TAQDkAQANAAYJyQ0TAQDkAQA1AAQKgSEAAg0ACQk0JNoDALoDAA0ACQk0JNoDALoDAAAA.Prìde:BAAANQAECgQIBAABNQAFFAYICwAVAL0WAA==.',
Ps='Psykopathik:BAAANQAECgMIBgAAAA==.',
Pu='Puddl:BAABNQAECoEeAAMUAAgJER4tFwC9AgAUAAgJER4tFwC9AgACAAgJyxf1KwARAgAAAA==.Purrsephone:BAAANQADCgEIAQAAAA==.',
Py='Pyrocutie:BAAANQADCggICwABNQAECgkJGwAGANIaAA==.',
Qa='Qaa:BAAANQAECgQICQAAAA==.',
Qh='Qhaos:BAAANQADCgYIBgABNQADCgYIDAADAAAAAA==.Qhaoss:BAAANQADCgYIDAAAAA==.',
Qi='Qirl:BAAANQADCgcIBwAAAA==.',
Qt='Qti:BAAANQADCgYIFAAAAA==.',
Qu='Quadnines:BAAANQAECgMIBgAAAA==.Quelivia:BAAANQADCgEIAQABNQAECgYIDAADAAAAAA==.Ques:BAAANQADCgYIEAAAAA==.Quesly:BAAANQAECgQIBgAAAA==.Quetzacoatl:BAAANQAECgUIDAAAAA==.',
Ra='Rabbit:BAAANQAFFAIIAgAAAA==.Racophorus:BAAANQADCggIGAAAAA==.Raffe:BAAANQAECgQICAAAAA==.Rammsteen:BAAANQADCggIDwAAAA==.Rarity:BAAANQAECgEIAwAAAA==.Ratarga:BAABNQAECoEaAAIUAAkJFyP/BQCJAwAUAAkJFyP/BQCJAwAAAA==.Rattroll:BAAANQAECgUIBwABNQAECgkJGgAUABcjAA==.Ratzgül:BAAANQAECggIBQAAAA==.Ravenaa:BAAANQAECgcIEgAAAA==.',
Re='Readycheck:BAAANQADCgEIAQAAAA==.Reallywanna:BAAANQAECgEIAQAAAA==.Reddragyn:BAAANQAECgQICAAAAA==.Reeves:BAAANQAECgEIAwAAAA==.Reggiez:BAAANQADCggIHwAAAA==.Reinbert:BAAANQAECgQIBAAAAA==.Rektski:BAAANQAECgcIEwAAAA==.Remixi:BAAANQABCgUIBwAAAA==.Renzer:BAAANQADCggIEQAAAA==.Reprosal:BAAANQAECgMIBAABNQAECgcIDAADAAAAAA==.Restasis:BAAANQADCgUIBwAAAA==.Retburn:BAAANQAECgcIEgAAAA==.Reveluv:BAAANQAECgUIBQAAAA==.',
Rh='Rheveus:BAAANQAECgcICwAAAA==.',
Ri='Rickehlol:BAAANQADCgYICgAAAA==.Righturn:BAAANQAECgQICQAAAA==.Rikkeh:BAAANQADCgIIAgAAAA==.Rinaera:BAAANQAECgMIBgAAAA==.',
Ro='Roahr:BAAANQADCgUIBAAAAA==.Rollinsmacks:BAAANQADCgIIAgAAAA==.Rollsforham:BAAANQADCggIFgAAAA==.Rondali:BAAANQADCggICAAAAA==.Rotheris:BAAANQAECgUIDgAAAA==.Rottentreats:BAAANQADCgYICQAAAA==.Rottie:BAABNQAECoEZAAMFAAkJ9xtuFwCpAgAFAAgJuBxuFwCpAgAQAAQJXxbpJAATAQAAAA==.',
Rs='Rski:BAAANQAECgEIAQAAAA==.',
Rt='Rts:BAABNQAECoEdAAISAAkJjiNqCwCFAwASAAkJjiNqCwCFAwAAAA==.',
Ru='Rufio:BAABNQAECoEaAAIMAAkJFyM9BACDAwAMAAkJFyM9BACDAwAAAA==.Rufiu:BAAANQAECgUIDAAAAA==.Rufiz:BAAANQAECgEIAQAAAA==.',
Ry='Ryjaxqt:BAAANQADCggICAABNQADCggICAADAAAAAA==.Ryogen:BAAANQAECgcIEwAAAA==.',
['Ré']='Rén:BAAANQADCgcIDAAAAA==.',
Sa='Saarahkin:BAAANQADCgcIDAAAAA==.Sablewhisper:BAAANQAECgQIBQAAAA==.Sabryel:BAAANQAECgYIEQAAAA==.Saintvyn:BAABNQAECoEbAAMVAAkJVB1SEgC1AgAVAAkJVB1SEgC1AgAWAAIJjRP/EQB2AAAAAA==.Salmonroll:BAAANQAECgMIBgAAAA==.Salos:BAAANQADCgYIBgAAAA==.Salvation:BAAANQADCggIDwAAAA==.Samael:BAAANQADCgUIBgAAAA==.Sandarah:BAABNQAECoEZAAMBAAkJLyGWAwCJAwABAAkJLyGWAwCJAwAbAAUJqhfDFQBzAQABNQAFFAYICwAVAIseAA==.Sapling:BAAANQAECgUICgAAAA==.Sathic:BAAANQAECgYIDQAAAA==.Satreser:BAAANQAECgQIBwAAAA==.Satyra:BAAANQADCgQIBAAAAA==.',
Sc='Scallywrath:BAAANQAECgIIAgAAAA==.Scaretale:BAAANQADCgQIBgAAAA==.Scribbles:BAABNQAECoEbAAMcAAkJqSFWBABqAwAcAAkJqSFWBABqAwAVAAEJBAy5hwA+AAAAAA==.Scribblesz:BAAANQADCgYIBgAAAA==.Scòtt:BAAANQADCgUIBQAAAA==.',
Se='Seanthepally:BAAANQAECgQIBQABNQAECgkJFgACAFIZAA==.Seantheshamm:BAABNQAECoEWAAICAAkJUhnUFQCoAgACAAkJUhnUFQCoAgAAAA==.Secihots:BAABNQAECoEWAAMRAAgJZhgIHQBhAQARAAUJVBYIHQBhAQAdAAQJDRkBQgAlAQAAAA==.Seidhkona:BAAANQADCgYIBgABNQAECgcICwADAAAAAA==.Seishirou:BAAANQADCggICAABNQAECgYICgADAAAAAA==.Serialheal:BAAANQAECgMIAwABNQAECgUICwADAAAAAA==.Sevalynn:BAAANQADCggIEAAAAA==.',
Sh='Shadalune:BAABNQAECoEbAAMOAAkJmiK8CABIAwAOAAkJLiK8CABIAwAJAAcJVR4zEACDAgAAAA==.Shamanelion:BAABNQAECoEXAAICAAkJ6BtQDgDtAgACAAkJ6BtQDgDtAgAAAA==.Shamnobi:BAAANQADCgQIBAAAAA==.Shazza:BAAANQADCgIIAgAAAA==.Shinso:BAAANQAFFAIIAQAAAA==.Shiwang:BAAANQAECgcICwAAAA==.Shockazuwu:BAABNQAECoEWAAMCAAgJbxReLwD+AQACAAgJbxReLwD+AQAUAAMJTRnldwDoAAAAAA==.Shocktagon:BAAANQADCgEIAQAAAA==.Shocktherapy:BAAANQAECgEIAQAAAA==.Shocktroopz:BAAANQADCgIIAgAAAA==.Shockzilla:BAAANQAECgMIAwAAAA==.Shockér:BAAANQAECgMIBQAAAA==.Shodoroki:BAAANQAECgYICgAAAA==.Shuu:BAAANQAECgYIDAAAAA==.Shwoidlord:BAAANQAECgQICAABNQAECggIFgACAG8UAA==.Shwoop:BAAANQAECgQIBAABNQAECggIFgACAG8UAA==.',
Si='Sigurrose:BAAANQAECgMICAAAAA==.Silëntshøt:BAAANQADCgEIAQAAAA==.',
Sk='Skitzosvnff:BAAANQAECgcIDwAAAA==.Skrai:BAAANQADCggIBgAAAA==.',
Sm='Smetrios:BAAANQADCggIEAABNQAECgcICwADAAAAAA==.Smokedh:BAAANQAECgQICAABNQAECgcIEwADAAAAAA==.Smokezug:BAAANQAECgcIEwAAAA==.',
Sn='Snorter:BAAANQADCggIDQAAAA==.Snowfury:BAAANQAECgEIAQABNQAECggIHAAYAHYhAA==.Snowlock:BAAANQADCgYIEAAAAA==.Snowrain:BAABNQAECoEZAAILAAgJbSGxDAAFAwALAAgJbSGxDAAFAwAAAA==.',
So='Sotek:BAAANQABCgIIAgAAAA==.Soulster:BAAANQADCgEIAQAAAA==.Sourdeath:BAAANQAECgMIBgAAAA==.',
Sp='Spinningbrew:BAAANQAECgQIBAAAAA==.Spinseason:BAAANQADCgMIAwAAAA==.Spit:BAAANQAECgEIAQAAAA==.',
Ss='Ssnoosnoo:BAAANQAECgIIAgAAAA==.',
St='Stanchion:BAAANQADCgUICAAAAA==.Steelmessiah:BAAANQADCgYIBgAAAA==.Stinko:BAAANQAECgIIAQABNQAFFAUICQAaAFYYAA==.Stonecrusade:BAAANQAECgMIBAAAAA==.Stonedhokage:BAAANQAECgcIEwAAAA==.Stopthebleed:BAAANQADCggIDwAAAA==.Sturdy:BAAANQADCgYIBgAAAA==.Sty:BAACNQAFFIEFAAIGAAMJdBBRBAAEAQAGAAMJdBBRBAAEAQA1AAQKgSAAAwYACQlBIQwEAHUDAAYACQkVIQwEAHUDAAcACAmMGasVAEoCAAAA.Ståb:BAAANQADCgYIBgABNQAECggIHAASAHARAA==.Stårr:BAAANQADCgYIBwAAAA==.',
Su='Suffering:BAAANQADCgYICwAAAA==.Suicideblond:BAAANQADCggIGQAAAA==.Supadrac:BAABNQAECoEaAAIaAAkJDhfoCACzAgAaAAkJDhfoCACzAgAAAA==.Surfnturf:BAAANQAFFAQICAAAAQ==.Surging:BAAANQAECgQIDAAAAA==.Suri:BAAANQAECgIIAgABNQAFFAEIAQADAAAAAA==.Surii:BAAANQAFFAEIAQAAAA==.',
Sw='Swaazz:BAAANQAECgYIEQAAAA==.Swampypants:BAAANQADCgQIBAAAAA==.Swerve:BAAANQAECgMIBAAAAA==.Swinybswipen:BAAANQAECggIAgAAAA==.',
Sy='Sykocious:BAAANQAECgYIEQAAAA==.Sylleria:BAAANQAECgEIAQAAAA==.Syllia:BAAANQAECgYICgABNQAECgcIEQADAAAAAA==.Syngatesx:BAAANQADCggIAQAAAA==.Syphilia:BAABNQAECoEYAAIHAAkJRRIrEQCIAgAHAAkJRRIrEQCIAgAAAA==.',
Sz='Szeto:BAAANQAECgUICAABNQAECgkJGQAHANEaAA==.',
['Sè']='Sèanthewarr:BAAANQAECgIIAgABNQAECgkJFgACAFIZAA==.',
Ta='Tacocát:BAAANQAECgIIBAABNQAFFAUIDAALAEsYAA==.Tacosback:BAAANQADCgEIAQABNQAFFAUIDAALAEsYAA==.Tacosdk:BAABNQAFFIEIAAILAAMJJR+dAgArAQALAAMJJR+dAgArAQABNQAFFAUIDAALAEsYAA==.Tacoslop:BAAANQAECggIEgABNQAFFAUIDAALAEsYAA==.Tacosneak:BAAANQAECgYICQABNQAFFAUIDAALAEsYAA==.Talonarayan:BAAANQADCggIGAAAAA==.Taote:BAAANQABCgIIAgAAAA==.',
Te='Teebonez:BAAANQAECgQIBgAAAA==.Teesdays:BAAANQABCgQICwAAAA==.Tetrâ:BAAANQADCgYIBgAAAA==.Tewasha:BAABNQAECoEZAAIeAAgJYh2uAwC5AgAeAAgJYh2uAwC5AgAAAA==.',
Th='Thalryn:BAAANQADCgMIAwAAAA==.Thaylen:BAAANQADCgYIBQAAAA==.Thedoofy:BAAANQAECgEIAQAAAA==.Thiccmage:BAAANQAECgUIBQABNQAECggIGAAHAM4hAA==.Thorskin:BAAANQADCgUIBQAAAA==.Threellamas:BAAANQAECgcIEAAAAA==.Thuggèr:BAAANQADCgQIBAAAAA==.Thunderchub:BAAANQAECgQIBAAAAA==.Thunderx:BAAANQADCgMIAwAAAA==.Thuringwethl:BAAANQADCgcIFwAAAA==.',
Ti='Tidyswet:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.Tinydonny:BAAANQADCgQIBQAAAA==.',
To='Tokyø:BAAANQADCgEIAQAAAA==.Tonylildik:BAAANQAECgEIAQABNQAECgkJIQASAEsfAA==.Toolh:BAAANQADCgUIBQAAAA==.Toopac:BAEBNQAECoEbAAQJAAkJNCLPBABTAwAJAAkJoyHPBABTAwAOAAMJUR6AkgDuAAAfAAMJbBk2CADEAAAAAA==.Totö:BAAANQAECgUIEQAAAA==.',
Tr='Tramana:BAAANQAECgYIDwAAAA==.Trashxbin:BAAANQADCgUIBQAAAA==.Trauk:BAAANQAFFAEIAQAAAA==.Triggéred:BAAANQAECgMIAwAAAA==.Triig:BAAANQAECgQIBgAAAA==.Trollcopter:BAAANQAECgMIBAABNQAECgQIBgADAAAAAA==.Trollwíthbow:BAAANQAECgQICAAAAA==.',
Tu='Turr:BAAANQADCgYICwAAAA==.',
Tw='Tweedledumb:BAAANQAECgQIBgAAAA==.Twìnky:BAABNQAECoEcAAMZAAkJLB8XAgBdAwAZAAkJLB8XAgBdAwACAAEJiwkhtAA0AAAAAA==.',
Ul='Ulfric:BAAANQADCgIIAgAAAA==.',
Un='Unbreakkable:BAAANQADCggICAABNQAECgkJGQAgAPsbAA==.Unclepete:BAAANQAECgYICQAAAA==.Unstobubble:BAAANQABCgIIAgAAAA==.',
Ur='Urouge:BAAANQADCgYIBgABNQAECgkJGQAHANEaAA==.',
Va='Vacula:BAAANQAECgQIBwAAAA==.Vaelyriana:BAAANQAECgQICAAAAA==.Valreaux:BAAANQAECgUICQAAAA==.Vandalism:BAAANQADCggIGgAAAA==.Vanian:BAAANQADCgUIBgAAAA==.Vanquìshh:BAAANQADCgUIBQAAAA==.',
Vd='Vdyr:BAAANQAECgIIAgAAAA==.',
Ve='Vex:BAAANQABCgMIAwAAAA==.',
Vi='Vilgefortz:BAAANQAECgUICwAAAA==.Vivelf:BAAANQADCggIAQAAAA==.',
Vo='Voidborn:BAAANQAECgUIDAAAAA==.Voidling:BAAANQAECgIIAwAAAA==.Voidturned:BAAANQADCgQIBAAAAA==.Vortexis:BAAANQAECgQIBgAAAA==.',
Vu='Vulpurra:BAAANQAECgQIBQAAAA==.Vurm:BAABNQAECoEgAAIKAAgJxSINEwAvAwAKAAgJxSINEwAvAwAAAA==.',
Vy='Vytamin:BAAANQAECgQIBQAAAA==.',
['Vâ']='Vâlinoth:BAAANQAECgYIDgAAAA==.',
['Vó']='Vólkan:BAAANQADCgcIGQAAAA==.',
Wa='Walkinghealz:BAAANQADCgQIBQABNQAECgQIBgADAAAAAA==.',
We='Weiss:BAAANQADCggICAAAAA==.Wengo:BAAANQADCgIIBAAAAA==.',
Wh='Whistlejinky:BAAANQADCgQIBAAAAA==.',
Wi='Willywonkie:BAAANQADCgQIBgAAAA==.Winbot:BAAANQAECgIIAgABNQAFFAMIBQAhABMQAA==.Windfrey:BAAANQAECgUIBwAAAA==.Windsong:BAAANQADCgUIBQAAAA==.Winghollow:BAAANQADCgIIAgAAAA==.Wintershock:BAAANQAECgcIEQAAAA==.Wisk:BAAANQAECggICwAAAA==.',
Wl='Wll:BAAANQAECgQIBgABNQAECgkJGQALADUcAA==.Wlx:BAABNQAECoEZAAMLAAkJNRxcFQCgAgALAAkJbBpcFQCgAgAPAAYJxR3GGADPAQAAAA==.',
Wo='Wobs:BAAANQAFFAEIAgAAAA==.Woopoles:BAAANQADCggIFAAAAA==.',
Wr='Wredgeek:BAAANQAECgQIBAAAAA==.',
Wy='Wy:BAAANQAECgMIAwAAAA==.',
Xa='Xavierboí:BAAANQAECgUIDQAAAA==.',
Xi='Xileon:BAAANQAECgMIBgAAAA==.',
Xo='Xombie:BAAANQADCgUIBQAAAA==.',
Ya='Yabishus:BAAANQAECgEIAQAAAA==.Yahboibangz:BAAANQAECgIIAwAAAA==.Yamajin:BAAANQADCgIIAgAAAA==.',
Yc='Ycetz:BAAANQADCgYICgABNQAECgQICQADAAAAAA==.',
Ye='Yelacsa:BAAANQAECgMIAwABNQAECggIFgACAG8UAA==.',
Yi='Yinan:BAAANQAECgIIAgAAAA==.',
Yo='Yoshu:BAAANQAECgUICgAAAA==.',
Yu='Yukyukyuk:BAAANQABCgQIBAAAAA==.',
Za='Zalarax:BAAANQAECggICAAAAA==.Zanthu:BAEANQADCgYIBgABNQAECgkJGwAJADQiAA==.Zanu:BAAANQADCgYICwAAAA==.Zardon:BAAANQADCgYIBgABNQAECgkJIQAEAJglAA==.',
Ze='Zecar:BAAANQADCgUIBQAAAA==.Zengard:BAAANQADCgYICAAAAA==.Zenkic:BAAANQADCgEIAQAAAA==.Zenlock:BAAANQADCgYIBgABNQAECgYIDAADAAAAAA==.',
Zi='Zivzs:BAAANQADCgIIAgAAAA==.Zivá:BAAANQABCgYICAAAAA==.',
Zo='Zoralari:BAAANQAECgUIDAAAAA==.Zorke:BAAANQAECgUICgAAAA==.',
Zu='Zulnas:BAAANQAECgcICwAAAA==.',
['Ön']='Önonta:BAAANQAECgIIAgAAAA==.Önotoes:BAAANQAECgMIBgAAAA==.',
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
