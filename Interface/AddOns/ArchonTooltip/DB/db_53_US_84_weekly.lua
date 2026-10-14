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

local lookup = {'DeathKnight-Blood','Shaman-Restoration','Hunter-BeastMastery','Warrior-Protection','Paladin-Protection','Monk-Windwalker','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Paladin-Holy','Unknown-Unknown','DemonHunter-Vengeance','Druid-Balance','Druid-Restoration','Druid-Guardian','Evoker-Devastation','Priest-Holy','Evoker-Augmentation','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','Paladin-Retribution','Mage-Frost','Mage-Arcane','Warlock-Destruction','DeathKnight-Frost','Rogue-Assassination','Shaman-Enhancement','Hunter-Marksmanship','Monk-Mistweaver','Shaman-Elemental','DeathKnight-Unholy',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abeblinkin:BAAANQADCgYICQAAAA==.Abraxîs:BAAANQAECgYIBwAAAA==.',
Ac='Acindis:BAABNQAECn8wAAIBAAkKzROyOgAYAgABAAkKzROyOgAYAgAAAA==.',
Ae='Aeless:BAAANQAECgQIBgAAAA==.Aelless:BAAANQADCgEIAQAAAA==.',
Ah='Ahzure:BAAANQAECgYICAABNQAECggIIwACAM8XAA==.',
Ai='Aithinne:BAAANQADCgUICQAAAA==.',
Al='Alch:BAAANQADCgQIBAAAAA==.Aleandi:BAAANQADCgUIBQAAAA==.Aledil:BAAANQAECgYICgAAAA==.Alynara:BAABNQAECn8iAAIDAAgK/BnfUAB6AgADAAgK/BnfUAB6AgAAAA==.',
Am='Amalthea:BAAANQAECgcIDgAAAA==.Amoredis:BAAANQABCggIEQAAAA==.',
An='Anume:BAAANQADCgYIDgAAAA==.Anwas:BAAANQABCgIIAgAAAA==.',
Ap='Apally:BAAANQADCgUIBQAAAA==.',
Ar='Aragan:BAAANQADCgQIBAAAAA==.Arellean:BAAANQADCgQIBAAAAA==.Arese:BAAANQAECgcIEQAAAA==.',
As='Asmodea:BAAANQADCgUJBQAAAA==.Asphonix:BAAANQAECgEIAQAAAA==.',
Az='Azzif:BAAANQAECgcICgAAAA==.',
Ba='Babybluz:BAAANQAECgIIBAAAAA==.Baifeng:BAAANQABCggIEwAAAA==.Bandayde:BAAANQADCgEIAQAAAA==.',
Be='Beauriley:BAABNQAECn8mAAIEAAgKWwvoGwB4AQAEAAgKWwvoGwB4AQAAAA==.Behomethan:BAAANQAECgcIDAAAAA==.Belorc:BAAANQADCgIIAgAAAA==.Berian:BAAANQAECgIIAgAAAA==.',
Bi='Bigpapafreez:BAAANQADCggIDQABNQAECgkJLwAFALsaAA==.Billbetaray:BAAANQAECgYICwAAAA==.',
Bl='Blux:BAAANQADCgEIAQAAAA==.Bløødsong:BAAANQADCgEIAQAAAA==.',
Bo='Bombchele:BAABNQAECn8WAAIGAAcKRx++GQBwAgAGAAcKRx++GQBwAgAAAA==.Bowogibrann:BAAANQADCgQIBAAAAA==.',
Br='Bratticusrex:BAABNQAECn8hAAIHAAgKiQbHFwAfAQAHAAgKiQbHFwAfAQAAAA==.Brazier:BAAANQADCggICAAAAA==.Bresowar:BAAANQADCgIIAgAAAA==.Brynthe:BAAANQADCgYICwAAAA==.',
Bu='Bunnylicious:BAABNQAECn8jAAICAAgKkCKeGQAJAwACAAgKkCKeGQAJAwAAAA==.Bunnymedic:BAAANQAECgMIAwABNQAECggIIwACAJAiAA==.',
Ca='Caebrylla:BAABNQAECn8XAAIDAAcK3xLOlwDUAQADAAcK3xLOlwDUAQAAAA==.Cajun:BAABNQAECn8XAAIIAAgKLBVLegAlAgAIAAgKLBVLegAlAgABNQAFFAUIFgAJAOMXAA==.Calistie:BAAANQABCgYIBwAAAA==.Callipygea:BAAANQADCgIIAgAAAA==.Camil:BAAANQADCgMIAwABNQAECggIJgADAOwLAA==.Cang:BAAANQABCggIGQAAAA==.Catalina:BAABNQAECn8qAAIKAAkKBx8hFgAkAwAKAAkKBx8hFgAkAwAAAA==.',
Ce='Cecimorte:BAABNQAECn8XAAIBAAcKOBQbTgC6AQABAAcKOBQbTgC6AQAAAA==.',
Ch='Chargeasap:BAAANQADCgUIBQAAAA==.Charttopper:BAAANQAECgQIBAABNQAECgYICQALAAAAAA==.Chinashop:BAAANQAECgMIAwABNQAECgcIFAAMADMgAA==.Chonker:BAABNQAECn8qAAMNAAgK+BMtPAAQAgANAAgK+BMtPAAQAgAOAAYKHRPeOQBMAQAAAA==.Chuckforrest:BAAANQADCgIIAgABNQAECgYIBgALAAAAAA==.',
Ci='Cihato:BAABNQAECn8oAAIPAAgKJheIFAAYAgAPAAgKJheIFAAYAgAAAA==.',
Cl='Claye:BAAANQAECgIIAgAAAA==.Cleveistic:BAAANQADCgUIBwABNQAECgIIBAALAAAAAA==.Cleveland:BAAANQAECgIIBAAAAA==.',
Co='Coldshoulder:BAAANQAECgYIEwAAAA==.Corelas:BAAANQAECgIIAwAAAA==.Couchdad:BAAANQADCggIFwABNQAECgEIAQALAAAAAA==.',
Cr='Crazymadman:BAAANQADCggIIAAAAA==.Crysallis:BAAANQADCggIHgAAAA==.',
Cy='Cynide:BAAANQADCgYJBgAAAA==.',
Da='Dall:BAAANQAECgIIAwAAAA==.Damo:BAAANQAECgYJCAAAAA==.Danale:BAAANQADCgYJCgAAAA==.Danknugz:BAAANQAECgUIEAAAAA==.Dawnson:BAAANQAECgYIEAAAAA==.',
De='Deathlich:BAAANQAECgYICwAAAA==.Demogless:BAAANQAECgMIAwAAAA==.Desyrel:BAAANQAECgIIAgABNQAECggIFgADAC0KAA==.',
Dh='Dharknight:BAAANQAECgQIBgAAAA==.Dharkuul:BAAANQABCgYICAABNQAECgQIBgALAAAAAA==.',
Di='Didimissfire:BAEBNQAECn8mAAIDAAgKxgq8iwDvAQADAAgKxgq8iwDvAQAAAA==.Diefatty:BAAANQADCgMIAwAAAA==.Dilaudid:BAAANQAECggICAAAAA==.',
Do='Doll:BAAANQADCgQIBAAAAA==.',
Dr='Draeven:BAAANQABCgIIAgAAAA==.Dranalis:BAAANQADCgYICAAAAA==.Dredlok:BAAANQADCgYIEAAAAA==.',
Du='Dumonster:BAAANQAECgQICAAAAA==.Dustdevil:BAAANQADCggICAABNQAECgcIFAAMADMgAA==.',
Ea='Eamishal:BAAANQADCgMIAwAAAA==.',
Ee='Eeaassyy:BAAANQADCgQIBQAAAA==.',
El='Elaraa:BAAANQADCgQIBAAAAA==.Eldorath:BAAANQAECgIIAgAAAA==.Elev:BAAANQADCgMIAwAAAA==.Elizabeth:BAAANQADCgUIBQAAAA==.',
Er='Eris:BAAANQADCggICAAAAA==.Erzascar:BAAANQAECgEIAQAAAA==.',
Es='Estrogen:BAABNQAECn8nAAIQAAgK0yVlAwBwAwAQAAgK0yVlAwBwAwAAAA==.',
Ev='Eventhorizon:BAAANQAECgYIAgAAAA==.Evolett:BAAANQADCgQIBAAAAA==.',
Fa='Fatbox:BAABNQAECn8jAAMHAAgK0R/vBADcAgAHAAgK0R/vBADcAgAIAAEKrA3ITwEyAAAAAA==.Fayth:BAABNQAECn8mAAIRAAgK3R2VMQCfAgARAAgK3R2VMQCfAgAAAA==.',
Fe='Fearkin:BAABNQAECn8XAAISAAgKYw3eCwCbAQASAAgKYw3eCwCbAQAAAA==.Fenastic:BAABNQAECn8gAAMTAAcKgQezuQBVAQATAAcKgQezuQBVAQAUAAEKtwcBMAA0AAAAAA==.Fermy:BAAANQABCgIIAQAAAA==.Feyrah:BAAANQAECgEIAQAAAA==.',
Fi='Fiobhe:BAAANQAECgIIAwAAAA==.Fixeruper:BAAANQAECgcIDQAAAA==.',
Fo='Fonz:BAAANQADCgYIBgABNQAECgQICQALAAAAAA==.',
Ge='Geauxt:BAAANQAECgQIBwABNQAFFAUIFgAJAOMXAA==.',
Gl='Glenlizzo:BAAANQADCgEJAQABNQAECgIIBAALAAAAAA==.Glenroyce:BAAANQAECgIIBAAAAA==.Gless:BAABNQAECn8kAAMEAAgKLAyxHABvAQAEAAgKLAyxHABvAQAIAAEKAAA5WwEnAAAAAA==.',
Gn='Gnoretreat:BAABNQAECn8kAAIIAAgKtRqoWwB2AgAIAAgKtRqoWwB2AgAAAA==.',
Go='Goss:BAAANQAECggICAAAAA==.',
Gw='Gwinnivor:BAAANQADCgcICAAAAA==.',
Ha='Haenus:BAAANQADCgMIAwAAAA==.Haill:BAAANQABCgIIAgABNQAECgUIDgALAAAAAA==.Hamhock:BAAANQAECgIIAgABNQAECggIIwAHANEfAA==.',
He='Hellìos:BAAANQADCgYIBgABNQAECgIIAgALAAAAAA==.',
Hy='Hyborian:BAAANQAECgUIDQABNQADCgIIAgALAAAAAA==.',
Ic='Icandy:BAAANQADCgMIAgAAAA==.Icecuber:BAAANQADCgMIAwAAAA==.',
Ih='Ihatepallys:BAAANQADCgYICQAAAA==.',
Ii='Iikeomgikr:BAABNQAECn8bAAIRAAkK/AtHZQDrAQARAAkK/AtHZQDrAQAAAA==.',
Il='Ilidank:BAABNQAECn8UAAIMAAcKMyAkBwCYAgAMAAcKMyAkBwCYAgAAAA==.Ilya:BAAANQAECgcIBwAAAA==.',
In='Indigo:BAABNQAECn8jAAICAAgKzxcOTwAlAgACAAgKzxcOTwAlAgAAAA==.Ineffablyss:BAAANQABCgYICAABNQAECgkJGwARAPwLAA==.Innron:BAABNQAECn8iAAIVAAgKjwwpPwC9AQAVAAgKjwwpPwC9AQAAAA==.',
Io='Iol:BAAANQADCgIIAgAAAA==.',
Ir='Irisblue:BAAANQADCgYIAwAAAA==.',
Ja='Jaque:BAAANQADCgYICwAAAA==.',
Je='Jeybieber:BAAANQAECgEIAQAAAA==.Jezzea:BAAANQADCgYICwAAAA==.',
Ji='Jinjix:BAAANQADCgYIDQAAAA==.',
Jo='Jolenee:BAAANQADCggIBwAAAA==.Jolike:BAAANQAECgEIAgAAAA==.Jonly:BAAANQADCgQIBwAAAA==.Jonoa:BAAANQAECgYIDAAAAA==.',
['Jú']='Júdgemental:BAABNQAECn8VAAMKAAgKCxfqSwA2AgAKAAgKCxfqSwA2AgAWAAEKAACFkgE8AAAAAA==.',
Ka='Kair:BAAANQADCgcIBwAAAA==.Kalsium:BAAANQADCgUJDAAAAA==.Kami:BAAANQAECgIIAwAAAA==.Kattastrophy:BAAANQAECgEIAQAAAA==.Katteya:BAAANQADCggILgAAAA==.Kattia:BAABNQAECn8kAAIDAAgKpAcomQDRAQADAAgKpAcomQDRAQAAAA==.',
Ki='Killinkair:BAAANQAECgYIDgAAAA==.Kinomihime:BAABNQAECn8mAAMXAAgKsxDIDQDPAQAXAAgKsxDIDQDPAQAYAAEKMAZywwE0AAAAAA==.Kirajoy:BAABNQAECn8jAAMZAAgKBgW5MwD0AAATAAcKvQQk0QAiAQAZAAcKYwK5MwD0AAAAAA==.Kisses:BAAANQADCgYICgAAAA==.',
Kn='Knyghtt:BAAANQAECgcIDQAAAA==.',
Kr='Kraviz:BAAANQADCgcICgAAAA==.Krystle:BAAANQAECgUIBQAAAA==.',
Le='Leftyloose:BAAANQADCgYIBAAAAA==.Leorna:BAAANQADCgQIBQAAAA==.',
Li='Lightcure:BAAANQAECgQIBwABNQAECggIJwAaAAEcAA==.Lilfonz:BAAANQAECgQICQAAAA==.Littlejohn:BAAANQAECgQIBwABNQAECgcIFAAMADMgAA==.',
Lo='Logarth:BAAANQAECgIIBAAAAA==.Londonfog:BAAANQADCggIEwAAAA==.Loppandload:BAAANQAECgEIAQAAAA==.Loppsang:BAAANQADCgEJAQAAAA==.Lorcan:BAABNQAECn8nAAIIAAgKex28WQB7AgAIAAgKex28WQB7AgAAAA==.',
Lr='Lroye:BAACNQAFFH8WAAMJAAUK4xfzBgCdAQAJAAUK4xfzBgCdAQAbAAEK2w14HwBIAAA1AAQKfzUAAwkACQqxJE0CAJADAAkACQqxJE0CAJADABsAAQo3DEaeADcAAAAA.',
Lu='Lucyfer:BAAANQADCgcIDQABNQAECggIFgADAC0KAA==.Lucyferr:BAAANQAECgQIDwABNQAECggIFgADAC0KAA==.Ludicrispeed:BAAANQADCgYIAwAAAA==.Luliak:BAAANQAECgIIAgABNQAFFAMICgAcAGIiAA==.Lunabren:BAAANQADCgcIBgAAAA==.Lunamina:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìllith:BAAANQAECgYIDwABNQAECgkJLwAWAAIfAA==.',
Ma='Madoka:BAABNQAECn8WAAIIAAkK/wp0uQCIAQAIAAkK/wp0uQCIAQAAAA==.Mariophra:BAAANQAECgYIEAAAAA==.Maxdemon:BAAANQADCgUIBQAAAA==.Maxpal:BAAANQADCgYIDgAAAA==.',
Mc='Mcnastyqt:BAAANQADCgIIAgAAAA==.',
Me='Mesdel:BAAANQAECgEIAQABNQAECggICgALAAAAAA==.',
Mi='Mikki:BAAANQADCgIIAgAAAA==.Misstorgo:BAAANQADCggILwAAAA==.',
Mo='Mohegian:BAAANQABCgQIAwAAAA==.Mokoko:BAAANQAECgQIBgAAAA==.Monfro:BAAANQAECgUICAAAAA==.Monnethir:BAAANQADCgUIBQAAAA==.Moogatoo:BAAANQAECgEIAQAAAA==.Moonbane:BAABNQAECn8mAAMZAAgK0Rz2BQCxAgAZAAgK0Rz2BQCxAgATAAQKZAy6+ADUAAAAAA==.Moonmist:BAAANQABCgUIBQABNQAECgUIDgALAAAAAA==.Mordecai:BAAANQAECgcIDwAAAA==.',
My='Myaquean:BAAANQADCgYIDgAAAA==.Mystogan:BAAANQADCgYIDgAAAA==.Myth:BAABNQAECn8jAAMNAAgK/RZjNwAuAgANAAgK/RZjNwAuAgAOAAMKNw8cWgCZAAAAAA==.Mythelea:BAAANQADCgYIBgAAAA==.',
Na='Naavi:BAAANQAECgIIAwAAAA==.Nakeefa:BAAANQADCgYIBgAAAA==.Natsuu:BAABNQAECn8gAAIDAAgKNg8iZwBDAgADAAgKNg8iZwBDAgAAAA==.',
Ne='Nefertiti:BAAANQADCggIAgAAAA==.Nekona:BAAANQADCgQIBAAAAA==.Neron:BAABNQAECn8vAAIWAAkKAh/LMAAFAwAWAAkKAh/LMAAFAwAAAA==.',
Ni='Niany:BAAANQAECgIIBAAAAA==.',
Nj='Njoror:BAAANQAECgIIAgAAAA==.',
No='Norky:BAAANQABCgUICQABNQAECgIIAgALAAAAAA==.Nottapally:BAAANQADCgQIBAABNQAECgYICQALAAAAAA==.',
Os='Ossiferous:BAAANQAECgYIDAAAAA==.',
Ou='Outerlimits:BAAANQAFFAEIAQAAAA==.',
Pa='Pamboo:BAABNQAECn8qAAIKAAgKiwuifQCdAQAKAAgKiwuifQCdAQAAAA==.Patticake:BAAANQAECggICAAAAA==.',
Pe='Pearle:BAAANQAECggICAAAAA==.Penthesilea:BAAANQABCgYIBwAAAA==.',
Po='Potatoslicer:BAAANQADCgQIBAAAAA==.',
Pr='Priestiô:BAAANQAECgUICQAAAA==.Pringo:BAAANQAECgYIDQAAAA==.',
Py='Pylea:BAAANQAECgEIAQAAAA==.',
Ra='Ramindizzle:BAABNQAECn8qAAIdAAgKKRKALQDcAQAdAAgKKRKALQDcAQAAAA==.Randomname:BAAANQAECggIDgABNQAECggIFQAKAAsXAA==.',
Re='Refreshing:BAAANQADCgUIBwAAAA==.Rekki:BAAANQAECgQICAABNQAECggIFgADAC0KAA==.Retastic:BAAANQADCgUIBQAAAA==.',
Ri='Rigmarole:BAAANQAECgYICwAAAA==.',
Ro='Rocksmasher:BAAANQADCgEIAQABNQAECgYICQALAAAAAA==.Ronun:BAAANQADCggICwAAAA==.Rook:BAAANQAECgEIAQAAAA==.Rooklyn:BAABNQAECn8nAAIKAAgK9w4+cgC+AQAKAAgK9w4+cgC+AQAAAA==.Roye:BAABNQAECn8nAAIWAAkKoCJnLQAQAwAWAAkKoCJnLQAQAwABNQAFFAUIFgAJAOMXAA==.',
Ru='Ruffiyo:BAAANQAECgYIBgABNQAECggIJwAaAAEcAA==.Rugrahh:BAAANQADCgYIBgAAAA==.Rugzco:BAABNQAECn8jAAIeAAkKiBiSEAByAgAeAAkKiBiSEAByAgAAAA==.Ruìn:BAAANQAECgUICgAAAA==.',
Ry='Ryalla:BAAANQABCgEIAQAAAA==.',
['Ræ']='Ræñ:BAAANQAECgcIBwAAAA==.',
Sa='Sabina:BAABNQAECn8iAAIfAAgKWQeniwCDAQAfAAgKWQeniwCDAQAAAA==.Sadako:BAAANQADCggILAABNQAECggIFgADAC0KAA==.Sadness:BAAANQADCggIGAAAAA==.Sadorick:BAAANQADCggIJAAAAA==.Sadôrick:BAAANQADCgcIBwAAAA==.Sageguy:BAAANQADCgcIDwAAAA==.Saintkitiara:BAAANQABCgMIAwAAAA==.Sango:BAABNQAECn8jAAIVAAkKZxBFMQAaAgAVAAkKZxBFMQAaAgAAAA==.Sarenity:BAAANQADCgYIBgAAAA==.Savagelykill:BAAANQADCggIDgAAAA==.',
Sc='Scotch:BAABNQAECn8jAAMWAAgKfRLdoQDYAQAWAAgKfRLdoQDYAQAFAAEKjxHmbwAvAAAAAA==.Scotchnwater:BAAANQADCgMIAwAAAA==.Scratchies:BAAANQAECgYICQAAAA==.',
Se='Seiwar:BAABNQAFFH8GAAIIAAMKqAe6JwC5AAAIAAMKqAe6JwC5AAAAAA==.',
Sh='Shadornia:BAAANQAECgMIBwAAAA==.Shadowcrwlr:BAAANQADCgQIBAAAAA==.Shamangroo:BAAANQADCgYIBgABNQADCggIHQALAAAAAA==.Shamanio:BAABNQAECn8rAAICAAkKvCLcCgBoAwACAAkKvCLcCgBoAwAAAA==.Shammbulance:BAAANQAECggICAABNQAECggIFQAKAAsXAA==.Shamsham:BAAANQABCgIIAgAAAA==.Sharaaz:BAAANQADCgUIBQAAAA==.Shatoya:BAAANQADCgcIAwAAAA==.',
Si='Silverytwo:BAAANQADCggIFgAAAA==.Silverywolfe:BAAANQAECgEIAQAAAA==.Sintia:BAAANQAECgYIBgABNQAECgkJJgARAJQjAA==.',
Sk='Skovak:BAAANQAECgQIBQAAAA==.Skoveth:BAAANQAECgEIAQAAAA==.',
So='Sorayae:BAABNQAECn8mAAIRAAkKlCOwCAB9AwARAAkKlCOwCAB9AwAAAA==.',
Sp='Specialk:BAAANQAECgEIAQAAAA==.Splooshh:BAAANQADCggIDgABNQAECggIJwAaAAEcAA==.',
St='Steeler:BAAANQAECgEIAQABNQADCgIIAgALAAAAAA==.Stinkfoot:BAABNQAECn8aAAIBAAcKqRXWSADRAQABAAcKqRXWSADRAQAAAA==.Stormkissed:BAAANQADCggILwAAAA==.Strawman:BAAANQAECgYIBwAAAA==.',
Su='Sugarush:BAAANQADCgQIBAABNQAECgUIDgALAAAAAA==.Sulvazud:BAAANQADCgEIAQAAAA==.Sunil:BAABNQAECn8jAAIRAAgKxRPxYAD6AQARAAgKxRPxYAD6AQAAAA==.',
Sy='Syclone:BAAANQAECgMIBgABNQAFFAIIBgAaAL0fAA==.',
Ta='Taetheras:BAAANQAECgUIBwAAAA==.Tahlyn:BAAANQAECgEIAQABNQAECggIIwACAM8XAA==.Tattianna:BAAANQADCggIGQAAAA==.Tavendar:BAABNQAECn8jAAMKAAcKkR9tUQAjAgAKAAYKcB9tUQAjAgAWAAIKSwWlhgFJAAABNQAECgIIAgALAAAAAA==.',
Tc='Tcshmaster:BAAANQAECgEIAQAAAA==.',
Te='Texgrebner:BAAANQAECgYIDgABNQAECgcIFAAMADMgAA==.',
Th='Theeyedoctor:BAAANQADCggIBwABNQAECgYICQALAAAAAA==.Thunderslate:BAAANQAECgYICQAAAA==.Thyrok:BAAANQAECgQIBwAAAA==.',
Ti='Tigreth:BAABNQAECn8oAAMWAAgKugsPswCzAQAWAAgKugsPswCzAQAFAAMKLQipWAB3AAAAAA==.Tinkerballa:BAAANQADCggJEgAAAA==.',
To='Toastal:BAAANQAECgIIAgAAAA==.Tokxi:BAAANQADCgIIAgABNQAECggIHgAFABkWAA==.Totemzasap:BAAANQAECgQICAAAAA==.',
Tr='Traductus:BAAANQAECgIIAgAAAA==.Tragik:BAABNQAECn8nAAIcAAgKSQpXGADdAQAcAAgKSQpXGADdAQAAAA==.Trisandra:BAAANQAECgIIAgAAAA==.',
Tu='Tuugadark:BAABNQAECn8nAAITAAgKfx4UNgCvAgATAAgKfx4UNgCvAgAAAA==.',
Tz='Tzulari:BAAANQAECgQIBAABNQAECgQIBgALAAAAAA==.',
Ul='Ulyaoth:BAAANQADCgUIBQAAAA==.',
Un='Unbroken:BAAANQADCgMIAwAAAA==.Unprepared:BAAANQABCgEIAQABNQAECgYIEwALAAAAAA==.',
Va='Vasdeferens:BAAANQABCgMIAwAAAA==.',
Ve='Vedros:BAAANQADCgYICQAAAA==.Verbina:BAAANQAECgQICQABNQAECggIIwACAM8XAA==.',
Vo='Vorukh:BAAANQAECgIIBAAAAA==.',
Wa='Warlockgroo:BAAANQADCgUIBQABNQADCggIHQALAAAAAA==.Warriorgroo:BAAANQADCggIHQAAAA==.',
Wi='Wickdlovly:BAAANQABCggIEAABNQAECgUIDgALAAAAAA==.Wickedslicks:BAABNQAECn8WAAINAAYKFh6JQQDuAQANAAYKFh6JQQDuAQAAAA==.',
Wr='Wreckshop:BAAANQADCgYIDwABNQAECgcIFgAGAEcfAA==.',
Xe='Xenøcide:BAAANQADCgcICwAAAA==.',
Xi='Xiatus:BAAANQAECgQICAABNQAECgkJMgAgAAclAA==.',
Xo='Xoren:BAAANQAECgEIAQABNQAECggIFgADAC0KAA==.',
Xx='Xxlockz:BAAANQADCgIIAgABNQAECgcIFwAKAEobAA==.Xxpallyz:BAABNQAECn8XAAIKAAcKShtBTgAvAgAKAAcKShtBTgAvAgAAAA==.',
Yo='Yohh:BAABNQAECn8jAAICAAkKSRKOSgA1AgACAAkKSRKOSgA1AgAAAA==.Yorie:BAAANQADCgMIAwAAAA==.',
Yu='Yuriko:BAABNQAECn8oAAIeAAgK3A8RHAC+AQAeAAgK3A8RHAC+AQAAAA==.',
Za='Zadory:BAAANQADCggIDAAAAA==.Zaidan:BAAANQADCggIDgAAAA==.',
Ze='Zendous:BAAANQAECgYIBgAAAA==.',
Zi='Zippitydooda:BAAANQAECgUIDgAAAA==.',
Zo='Zodiacc:BAABNQAECn8mAAIPAAgKcSDpBwD/AgAPAAgKcSDpBwD/AgAAAA==.Zornhealer:BAAANQADCggICAABNQAECgEIAQALAAAAAA==.Zorrn:BAAANQAECgEIAQAAAA==.',
['Zí']='Zílch:BAAANQAECgEIAQAAAA==.',
['Zî']='Zîlch:BAAANQADCgcIBwAAAA==.',
['Zö']='Zölä:BAAANQAECgQIBwABNQAECgYIBwALAAAAAA==.',
['Çh']='Çhrìs:BAAANQAECgQICAAAAA==.',
['Çú']='Çúrsè:BAAANQADCgIIAwAAAA==.',
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
