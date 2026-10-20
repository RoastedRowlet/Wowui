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

local lookup = {'DeathKnight-Blood','Shaman-Restoration','Hunter-BeastMastery','Warlock-Demonology','Warrior-Protection','Warrior-Fury','Paladin-Protection','Monk-Windwalker','Warrior-Arms','Rogue-Subtlety','Paladin-Holy','Unknown-Unknown','DemonHunter-Vengeance','Druid-Balance','Druid-Restoration','Druid-Guardian','Mage-Arcane','Mage-Frost','Evoker-Devastation','Priest-Holy','Evoker-Augmentation','Warlock-Affliction','DemonHunter-Havoc','Paladin-Retribution','Warlock-Destruction','Rogue-Assassination','Shaman-Enhancement','Priest-Shadow','Hunter-Marksmanship','Monk-Mistweaver','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aardz:BAAANQADCggICAAAAA==.',
Ab='Abeblinkin:BAAANQADCgYICQAAAA==.Abraxîs:BAAANQAECgYIBwAAAA==.',
Ac='Acindis:BAABNQAECn8wAAIBAAkKzRNJOwAYAgABAAkKzRNJOwAYAgAAAA==.',
Ae='Aeless:BAAANQAECgQIBgAAAA==.Aelless:BAAANQADCgEIAQAAAA==.',
Ah='Ahzure:BAAANQAECgcIDgABNQAECgkJJQACAAEXAA==.',
Ai='Aithinne:BAAANQADCgUICQAAAA==.',
Al='Alch:BAAANQADCgQICAAAAA==.Aleandi:BAAANQADCgUIBQAAAA==.Aledil:BAAANQAECgYICgAAAA==.Alynara:BAABNQAECn8pAAIDAAoKchcyMABgAQADAAoKchcyMABgAQAAAA==.',
Am='Amalthea:BAABNQAECn8WAAIEAAkK/AVgtQBkAQAEAAkK/AVgtQBkAQAAAA==.Amoredis:BAAANQABCggIEwAAAA==.',
An='Anume:BAAANQADCgYIDgAAAA==.Anwas:BAAANQABCgIIAgAAAA==.',
Ap='Apally:BAAANQADCgUIBQAAAA==.',
Ar='Aragan:BAAANQADCgQIBAAAAA==.Arellean:BAAANQADCgQIBAAAAA==.Arese:BAAANQAECgcIEQAAAA==.',
As='Asmodea:BAAANQADCgUIBQAAAA==.Asphonix:BAAANQAECgEIAQAAAA==.',
Az='Azzif:BAAANQAECggIDwAAAA==.',
Ba='Babybluz:BAAANQAECgIIBAAAAA==.Baifeng:BAAANQABCggIFQAAAA==.Bandayde:BAAANQADCgYIBQAAAA==.',
Be='Beauriley:BAABNQAECn8qAAMFAAoKSQpMHAB4AQAFAAkK1QpMHAB4AQAGAAEKdAYNGQAnAAAAAA==.Behomethan:BAAANQAECgcIDAAAAA==.Belorc:BAAANQADCgIIAgAAAA==.Berian:BAAANQAECgIIAgAAAA==.',
Bi='Bigpapafreez:BAAANQADCggIDQABNQAECgoKOgAHAJIaAA==.Billbetaray:BAAANQAECgYICwAAAA==.',
Bl='Blux:BAAANQADCgEIAQAAAA==.Bløødsong:BAAANQADCgEIAQAAAA==.',
Bo='Bombchele:BAABNQAECn8eAAIIAAgKmB0UAgBQAgAIAAgKmB0UAgBQAgAAAA==.Bowogibrann:BAAANQADCgQIBAAAAA==.',
Br='Bratticusrex:BAABNQAECn8jAAIGAAgKiQb2FwAgAQAGAAgKiQb2FwAgAQAAAA==.Brazier:BAAANQADCggICAAAAA==.Bresowar:BAAANQADCgIIAgAAAA==.Brynthe:BAAANQADCgYICwAAAA==.',
Bu='Bunnylicious:BAABNQAECn8rAAICAAkKhSWFAQBlAwACAAkKhSWFAQBlAwAAAA==.Bunnymedic:BAAANQAECgMIAwABNQAECgkJKwACAIUlAA==.',
Ca='Caebrylla:BAABNQAECn8aAAIDAAcK3xIMmgDTAQADAAcK3xIMmgDTAQAAAA==.Cajun:BAABNQAECn8gAAIJAAkKaBSGFgCuAQAJAAkKaBSGFgCuAQABNQAFFAUIGAAKAOMXAA==.Calistie:BAAANQABCgYIBwAAAA==.Callipygea:BAAANQADCgIIAgAAAA==.Camil:BAAANQADCgMIAwABNQAECgkJKAADAGkLAA==.Cang:BAAANQABCggIGwAAAA==.Catalina:BAABNQAECn8wAAILAAoKsB1rFgAkAwALAAoKsB1rFgAkAwAAAA==.',
Ce='Cecimorte:BAABNQAECn8cAAIBAAcKOBSUJQDfAAABAAcKOBSUJQDfAAAAAA==.',
Ch='Chargeasap:BAAANQADCgUIBQAAAA==.Charttopper:BAAANQAECgQIBAABNQAECggIEgAMAAAAAA==.Chinashop:BAAANQAECgQIAwABNQAECggIFgANAOMgAA==.Chonker:BAABNQAECn8xAAMOAAoKehLPPAAQAgAOAAgK+BPPPAAQAgAPAAgKCRMHEQA/AQAAAA==.Chuckforrest:BAAANQADCgIIAgABNQAECgYIBgAMAAAAAA==.',
Ci='Cihato:BAABNQAECn8vAAIQAAoKcRiXBwCFAQAQAAoKcRiXBwCFAQAAAA==.',
Cl='Claye:BAAANQAECgIIAgAAAA==.Cleveistic:BAAANQADCgUIBwABNQAECgIIBAAMAAAAAA==.Cleveland:BAAANQAECgIIBAAAAA==.',
Co='Coldshoulder:BAABNQAECn8aAAMRAAcKaROGdQDSAAARAAYK8BKGdQDSAAASAAIK7BPvLgCHAAAAAA==.Corelas:BAAANQAECgIIAwAAAA==.Couchdad:BAAANQAECgIIAQABNQAECgIIAgAMAAAAAA==.',
Cr='Crazymadman:BAAANQADCggIIQAAAA==.Crysallis:BAAANQADCggIHgAAAA==.',
Cy='Cynide:BAAANQADCgYJBgAAAA==.Cyyrene:BAAANQABCgEIAQABNQAECgcIEgAMAAAAAA==.',
Da='Dall:BAAANQAECgIIAwAAAA==.Damo:BAAANQAECgYJCAAAAA==.Danale:BAAANQADCgYJCgAAAA==.Danknugz:BAAANQAECgYIEQAAAA==.Dawnson:BAABNQAECn8XAAILAAcKBRv4EgC7AQALAAcKBRv4EgC7AQAAAA==.',
De='Deadscream:BAAANQAECggIBgAAAA==.Deathlich:BAAANQAECgYICwAAAA==.Demogless:BAAANQAECgMIAwAAAA==.Desyrel:BAAANQAECgIIAgABNQAECgYIFAARAM0CAA==.',
Dh='Dharknight:BAAANQAECgQIBgAAAA==.',
Di='Didimissfire:BAEBNQAECn8sAAIDAAkKXAqwPwA3AQADAAkKXAqwPwA3AQAAAA==.Diefatty:BAAANQADCgMIAwAAAA==.',
Do='Doll:BAAANQADCgQIBAAAAA==.',
Dr='Draeven:BAAANQAECgUIBQAAAA==.Dranalis:BAAANQADCgYICAAAAA==.Dredlok:BAAANQADCgYIEAAAAA==.',
Du='Dumonster:BAAANQAECgQICQAAAA==.Dustdevil:BAAANQAECgEIAQABNQAECggIFgANAOMgAA==.',
Ee='Eeaassyy:BAAANQADCgQIBgAAAA==.',
El='Elaraa:BAAANQADCgQIBAAAAA==.Eldorath:BAAANQAECgIIAgAAAA==.Elev:BAAANQADCgMIAwAAAA==.Elizabeth:BAAANQADCgUIBQAAAA==.',
Er='Eris:BAAANQADCggICAAAAA==.Erzascar:BAAANQAECgEIAQAAAA==.',
Es='Estrogen:BAABNQAECn8pAAITAAkKjSV+AwBvAwATAAkKjSV+AwBvAwAAAA==.',
Ev='Eventhorizon:BAAANQAECgYIAgAAAA==.Evolett:BAAANQADCgQIBAAAAA==.',
Fa='Fatbox:BAABNQAECn8rAAMGAAkKGx+uAABvAgAGAAkKGx+uAABvAgAJAAEKrA0uVAEyAAAAAA==.Fayth:BAABNQAECn8tAAIUAAoKHB1xFgC+AQAUAAoKHB1xFgC+AQAAAA==.',
Fe='Fearkin:BAABNQAECn8fAAIVAAkK/wu2AgA8AQAVAAkK/wu2AgA8AQAAAA==.Fenastic:BAABNQAECn8hAAMEAAcKgQftuwBVAQAEAAcKgQftuwBVAQAWAAEKtwd2MAA0AAAAAA==.Feyrah:BAAANQAECgEIAQAAAA==.',
Fi='Finraziel:BAAANQABCgQIAwAAAA==.Fiobhe:BAAANQAECgIIAwAAAA==.Fixeruper:BAAANQAECggIDQAAAA==.',
Fo='Fonz:BAAANQADCgYIBgABNQAECgQIDQAMAAAAAA==.',
['Fí']='Físter:BAAANQADCgMIAwABNQAECgQIAgAMAAAAAA==.',
Ga='Gazember:BAAANQAECgEIAQABNQAECggIEQAMAAAAAA==.',
Ge='Geauxt:BAAANQAECgQIBwABNQAFFAUIGAAKAOMXAA==.',
Gl='Glenlizzo:BAAANQADCgEJAQABNQAECgIIBAAMAAAAAA==.Glenroyce:BAAANQAECgIIBAAAAA==.Gless:BAABNQAECn8sAAMFAAkKsQpXCQAdAQAFAAkKsQpXCQAdAQAJAAEKAAC1XwEnAAAAAA==.',
Gn='Gnoretreat:BAABNQAECn8rAAIJAAoKwxVPIgB7AQAJAAoKwxVPIgB7AQAAAA==.',
Go='Goss:BAAANQAECggICAAAAA==.',
Gw='Gwinnivor:BAAANQADCgcICAAAAA==.',
Ha='Haenus:BAAANQADCgMIAwAAAA==.Haill:BAAANQABCgIIAgABNQAECgcIFwACAN8bAA==.Hamhock:BAAANQAECgIIAgABNQAECgkJKwAGABsfAA==.',
He='Hellìos:BAAANQADCgYIBgABNQAECgIIAgAMAAAAAA==.',
Hy='Hyborian:BAABNQAECn8WAAIDAAcK5wyCQwAuAQADAAcK5wyCQwAuAQABNQADCgIIAgAMAAAAAA==.',
Ic='Icandy:BAAANQADCgMIAgAAAA==.Icecuber:BAAANQADCgQIBQAAAA==.',
Ih='Ihatepallys:BAAANQADCgYICQAAAA==.',
Ii='Iikeomgikr:BAABNQAECn8hAAIUAAoKdg3dKwBNAQAUAAoKdg3dKwBNAQAAAA==.',
Il='Ilidank:BAABNQAECn8WAAINAAgK4yA8BwCYAgANAAgK4yA8BwCYAgAAAA==.Ilya:BAAANQAECgcIBwAAAA==.',
In='Indigo:BAABNQAECn8lAAICAAkKARcgUAAlAgACAAkKARcgUAAlAgAAAA==.Ineffablyss:BAAANQAECgYIBgABNQAECgoKIQAUAHYNAA==.Innron:BAABNQAECn8mAAIXAAkKJgzmPwC9AQAXAAkKJgzmPwC9AQAAAA==.',
Io='Iol:BAAANQADCgIIAgAAAA==.',
Ir='Irisblue:BAAANQADCgYIAwAAAA==.',
Ja='Jaque:BAAANQADCgYICwAAAA==.',
Je='Jeybieber:BAAANQAECgEIAgAAAA==.Jezzea:BAAANQADCgYICwAAAA==.',
Ji='Jinjix:BAAANQADCgYIDQAAAA==.',
Jo='Jolenee:BAAANQAECgEIAQAAAA==.Jolike:BAAANQAECgEIAgAAAA==.Jonly:BAAANQADCgQIBwAAAA==.Jonoa:BAAANQAECgYIDAAAAA==.',
['Jú']='Júdgemental:BAABNQAECn8aAAMLAAkKVhbWIQBeAQALAAkKVhbWIQBeAQAYAAEKAAB9mAE8AAAAAA==.',
Ka='Kaelae:BAAANQABCgUIBQABNQAECgkJKQAUAJQjAA==.Kair:BAAANQADCgcIBwAAAA==.Kalsium:BAAANQADCgUJDAAAAA==.Kami:BAAANQAECgIIAwAAAA==.Kattastrophy:BAAANQAECgEIAQAAAA==.Katteya:BAAANQADCggINgAAAA==.Kattia:BAABNQAECn8sAAIDAAkKpwfCLwBhAQADAAkKpwfCLwBhAQAAAA==.',
Ki='Killinkair:BAAANQAECgYIDgAAAA==.Kinomihime:BAABNQAECn8sAAMSAAkKbA/qDQDPAQASAAkKbA/qDQDPAQARAAEKMAa+xwE0AAAAAA==.Kirajoy:BAABNQAECn8rAAMEAAkKoAUSLgA+AQAEAAgKYgUSLgA+AQAZAAcKYwLiMwD0AAAAAA==.Kisses:BAAANQADCgYICgAAAA==.',
Kn='Knyghtt:BAAANQAECgcIEgAAAA==.',
Kr='Kraviz:BAAANQADCgcICgAAAA==.Krombopolous:BAAANQADCggIBwABNQAECggIJwADACcLAA==.Krystle:BAAANQAECgYIBgAAAA==.',
Le='Leftyloose:BAAANQADCgYIBAAAAA==.Leorna:BAAANQADCgQIBQAAAA==.',
Li='Lightcure:BAAANQAECgQIBwABNQAECggICwAMAAAAAA==.Lilfonz:BAAANQAECgQIDQAAAA==.Littlejohn:BAAANQAECgQIBwABNQAECggIFgANAOMgAA==.',
Lo='Logarth:BAAANQAECgMIBQAAAA==.Londonfog:BAAANQADCggIEwAAAA==.Loppandload:BAAANQAECgEIAQAAAA==.Loppsang:BAAANQADCgYIBQAAAA==.Lorcan:BAABNQAECn8uAAIJAAoKsB7DDwDaAQAJAAoKsB7DDwDaAQAAAA==.',
Lr='Lroye:BAACNQAFFH8YAAMKAAUK4xcfBwCdAQAKAAUK4xcfBwCdAQAaAAEK2w0uIABIAAA1AAQKfzoAAwoACgoXI1QCAI8DAAoACgoXI1QCAI8DABoAAQrOG/o/AFoAAAAA.',
Lu='Lucyfer:BAAANQADCgcIDQABNQAECgYIFAARAM0CAA==.Lucyferr:BAABNQAECn8UAAIRAAYKzQK5ggG/AAARAAYKzQK5ggG/AAAAAA==.Ludicrispeed:BAAANQADCgYIAwAAAA==.Luliak:BAAANQAECgIIAgABNQAFFAQICwAbAGIiAA==.Lunabren:BAAANQADCgcIBgAAAA==.Lunamina:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìllith:BAABNQAECn8VAAMUAAcKhQ58lwBPAQAUAAYKqw18lwBPAQAcAAYKfgoIEgD9AAABNQAECgoKNwAYAIgdAA==.',
Ma='Madoka:BAABNQAECn8cAAIJAAoK9A1hTgABAQAJAAoK9A1hTgABAQAAAA==.Mariophra:BAABNQAECn8XAAICAAcKjRIDJgBLAQACAAcKjRIDJgBLAQAAAA==.Maxdemon:BAAANQADCgUIBQAAAA==.Maxpal:BAAANQADCgYIDgAAAA==.',
Mc='Mcnastyqt:BAAANQADCgIIAgAAAA==.',
Me='Mesdel:BAAANQAECgEIAQABNQAECggICwAMAAAAAA==.',
Mi='Mikki:BAAANQADCgIIAgAAAA==.Misstorgo:BAAANQAECgIIAgAAAA==.',
Mo='Mohegian:BAAANQABCgQIAwAAAA==.Mokoko:BAAANQAECgYICgAAAA==.Momoka:BAAANQAECgQICQAAAA==.Monfro:BAAANQAECgYICAAAAA==.Monnethir:BAAANQADCgUIBQAAAA==.Moogatoo:BAAANQAECgEIAQAAAA==.Moonbane:BAABNQAECn8sAAMZAAkKXh3+BQCwAgAZAAkKXh3+BQCwAgAEAAQKZAzL+wDUAAAAAA==.Moonmist:BAAANQABCgUIBQABNQAECgcIFwACAN8bAA==.Mordecai:BAAANQAECggIEgAAAA==.',
My='Myaquean:BAAANQADCgYIDgAAAA==.Mystogan:BAAANQADCgYIDgAAAA==.Myth:BAABNQAECn8nAAMOAAkK3hX9NwAuAgAOAAkK3hX9NwAuAgAPAAQKnBK9KwCKAAAAAA==.Mythelea:BAAANQADCgYIBgAAAA==.',
Na='Naavi:BAAANQAECgIIAwAAAA==.Nakeefa:BAAANQADCgYIBgAAAA==.Natsuu:BAABNQAECn8oAAIDAAkKNQ8KFwC/AQADAAkKNQ8KFwC/AQAAAA==.',
Ne='Nefertiti:BAAANQADCggIAgAAAA==.Nekona:BAAANQADCgQIBAAAAA==.Neron:BAABNQAECn83AAIYAAoKiB2dGgC4AQAYAAoKiB2dGgC4AQAAAA==.',
Ni='Niany:BAAANQAECgIIBAAAAA==.',
Nj='Njoror:BAAANQAECgIIAgAAAA==.',
No='Nonoffensive:BAAANQADCggIDwAAAA==.Norky:BAAANQABCgUICQABNQAECgIIAgAMAAAAAA==.Nottapally:BAAANQADCgQIBAABNQAECggIEgAMAAAAAA==.',
Os='Ossiferous:BAAANQAECgYIDgAAAA==.',
Ou='Outerlimits:BAAANQAECgcIEgAAAA==.',
Pa='Pamboo:BAABNQAECn8xAAILAAoKrQs7HwBsAQALAAoKrQs7HwBsAQAAAA==.Patticake:BAAANQAECggICAAAAA==.',
Pe='Pearle:BAAANQAECggICAAAAA==.Penthesilea:BAAANQABCggICQAAAA==.',
Po='Potatoslicer:BAAANQADCgQIBAAAAA==.',
Pr='Priestiô:BAAANQAECgUICgAAAA==.Pringo:BAAANQAECgcIDgAAAA==.',
Py='Pylea:BAAANQAECgEIAQAAAA==.',
Ra='Ramindizzle:BAABNQAECn8xAAIdAAoKexCbBwBrAQAdAAoKexCbBwBrAQAAAA==.Randomname:BAABNQAECn8VAAIDAAkK9hSxOgBDAQADAAkK9hSxOgBDAQABNQAECgkJGgALAFYWAA==.',
Re='Refreshing:BAAANQADCgcIDAAAAA==.Rekki:BAAANQAECgUICAABNQAECgYIFAARAM0CAA==.Retastic:BAAANQADCgUIBQAAAA==.',
Ri='Rigmarole:BAAANQAECgcICwAAAA==.',
Ro='Rocksmasher:BAAANQADCgEIAQABNQAECggIEgAMAAAAAA==.Ronun:BAAANQADCggICwAAAA==.Rook:BAAANQAECgEIAQAAAA==.Rooklyn:BAABNQAECn8uAAILAAoKTw86HAB9AQALAAoKTw86HAB9AQAAAA==.Roye:BAABNQAECn8tAAIYAAoKOiEzFQDUAQAYAAoKOiEzFQDUAQABNQAFFAUIGAAKAOMXAA==.',
Ru='Ruffiyo:BAAANQAECggICwAAAA==.Rugrahh:BAAANQADCgYIBgAAAA==.Rugzco:BAABNQAECn8oAAIeAAoKPBfOEAByAgAeAAoKPBfOEAByAgAAAA==.Ruìn:BAAANQAECgUICgAAAA==.',
Ry='Ryalla:BAAANQABCgEIAQAAAA==.',
['Ræ']='Ræñ:BAAANQAECgcIBwAAAA==.',
Sa='Sabina:BAABNQAECn8pAAIfAAoK+AYoMgD3AAAfAAoK+AYoMgD3AAAAAA==.Sadako:BAAANQAECgEIAQABNQAECgYIFAARAM0CAA==.Sadness:BAAANQADCggIIAAAAA==.Sadorick:BAAANQADCggILAAAAA==.Sadôrick:BAAANQADCgcIBwAAAA==.Sageguy:BAAANQADCgcIDwAAAA==.Saintkitiara:BAAANQABCgMIAwAAAA==.Sango:BAABNQAECn8lAAIXAAkKZxD1MQAaAgAXAAkKZxD1MQAaAgAAAA==.Sarenity:BAAANQADCgcIDQAAAA==.Savagelykill:BAAANQADCggIDgAAAA==.',
Sc='Scotch:BAABNQAECn8pAAMYAAkKoRFzSQAyAQAYAAkKoRFzSQAyAQAHAAEKjxFIcQAuAAAAAA==.Scotchnwater:BAAANQAECgIIAgAAAA==.Scratchies:BAAANQAECgYICQAAAA==.',
Se='Seiwar:BAABNQAFFH8GAAIJAAMKqAd9KAC5AAAJAAMKqAd9KAC5AAAAAA==.',
Sh='Shadornia:BAAANQAECgMIBwAAAA==.Shadowcrwlr:BAAANQADCgQIBAAAAA==.Shamangroo:BAAANQADCgYIBgABNQADCggIJQAMAAAAAA==.Shamanio:BAABNQAECn80AAMCAAoKhCQLCwBoAwACAAoKhCQLCwBoAwAfAAEKCxR9gABFAAAAAA==.Shammbulance:BAAANQAECggIDAABNQAECgkJGgALAFYWAA==.Sharaaz:BAAANQADCgUIBQAAAA==.Shatoya:BAAANQADCgcIAwAAAA==.',
Si='Silverytwo:BAAANQADCggIFgAAAA==.Silverywolfe:BAAANQAECgEIAQAAAA==.Simony:BAAANQADCggICAABNQAECgYIFAARAM0CAA==.Sintia:BAAANQAECgYICQABNQAECgkJKQAUAJQjAA==.',
Sk='Skovak:BAAANQAECgUIBQAAAA==.Skoveth:BAAANQAECgIIAQAAAA==.',
So='Sorayae:BAABNQAECn8pAAIUAAkKlCPyCAB8AwAUAAkKlCPyCAB8AwAAAA==.',
Sp='Specialk:BAAANQAECgEIAQAAAA==.Splooshh:BAAANQADCggIDgABNQAECggICwAMAAAAAA==.',
St='Steeler:BAAANQAECgEIAQABNQADCgIIAgAMAAAAAA==.Stinkfoot:BAABNQAECn8bAAIBAAgKexSlSQDRAQABAAgKexSlSQDRAQAAAA==.Stormkissed:BAAANQAECgIIAgAAAA==.Strawman:BAAANQAECgYICwAAAA==.',
Su='Sugarush:BAAANQADCgQIBAABNQAECgcIFwACAN8bAA==.Sulvazud:BAAANQADCgEIAQAAAA==.Sunil:BAABNQAECn8mAAIUAAkKUBQqYgD6AQAUAAkKUBQqYgD6AQAAAA==.',
Sy='Syclone:BAAANQAECgMIBgABNQAFFAIIBgAgAL0fAA==.Sypha:BAAANQAECgUICgAAAA==.',
Ta='Taetheras:BAAANQAECgYIBwAAAA==.Tahlyn:BAAANQAECgEIAQABNQAECgkJJQACAAEXAA==.Tattianna:BAAANQADCggIGQAAAA==.Tavendar:BAABNQAECn8mAAMLAAoKQxtTUgAjAgALAAkKsxpTUgAjAgAYAAIKSwV0jAFJAAABNQAECgIIAgAMAAAAAA==.Taírn:BAAANQADCgEIAQABNQAECgQIAgAMAAAAAA==.',
Tc='Tcshmaster:BAAANQAECgEIAQAAAA==.',
Te='Texgrebner:BAAANQAECgYIDgABNQAECggIFgANAOMgAA==.',
Th='Theeyedoctor:BAAANQADCggIBwABNQAECggIEgAMAAAAAA==.Thunderslate:BAAANQAECggIEgAAAA==.Thyrok:BAAANQAECgQIBwAAAA==.',
Ti='Tigreth:BAABNQAECn8vAAMYAAoKAwuttQCzAQAYAAoKAwuttQCzAQAHAAUK+wenWQB3AAAAAA==.Tinkerballa:BAAANQADCggJEgAAAA==.',
To='Toastal:BAAANQAECgIIAgAAAA==.Tokxi:BAAANQADCgIIAgABNQAECgkJIQAHAAkUAA==.Totemzasap:BAAANQAECgQICAAAAA==.',
Tr='Traductus:BAAANQAECgIIAgAAAA==.Tragik:BAABNQAECn8uAAIbAAoKWAnACABoAQAbAAoKWAnACABoAQAAAA==.Trisandra:BAAANQAECgMIAwAAAA==.',
Tu='Tuugadark:BAABNQAECn8rAAIEAAoKYBpfNwCuAgAEAAoKYBpfNwCuAgAAAA==.',
Tz='Tzulari:BAAANQAECgQIBQABNQAECgQIBgAMAAAAAA==.',
Ul='Ulyaoth:BAAANQADCgUIBQAAAA==.',
Un='Unbroken:BAAANQADCgMIAwAAAA==.Unprepared:BAAANQABCgEIAQABNQAECgcIGgARAGkTAA==.',
Va='Vasdeferens:BAAANQABCgMIAwAAAA==.',
Ve='Vedros:BAAANQADCgYICQAAAA==.Verbina:BAAANQAECgQICwABNQAECgkJJQACAAEXAA==.',
Vo='Vorukh:BAAANQAECgIIBAAAAA==.',
Wa='Warlockgroo:BAAANQADCgcICgABNQADCggIJQAMAAAAAA==.Warriorgroo:BAAANQADCggIJQAAAA==.',
Wi='Wickdlovly:BAAANQABCggIEAABNQAECgcIFwACAN8bAA==.Wickedslicks:BAABNQAECn8XAAIOAAcKlx0rQgDuAQAOAAcKlx0rQgDuAQAAAA==.',
Wr='Wreckshop:BAAANQADCgYIDwABNQAECggIHgAIAJgdAA==.',
Xe='Xenøcide:BAAANQADCgcICwAAAA==.',
Xi='Xiatus:BAAANQAECgUICQABNQAECgoKOwAhAAYlAA==.',
Xo='Xoren:BAAANQAECgEIAQABNQAECgYIFAARAM0CAA==.',
Xx='Xxlockz:BAAANQADCgIIAgABNQAECgcIGQALAK8bAA==.Xxpallyz:BAABNQAECn8ZAAILAAcKrxsNTwAvAgALAAcKrxsNTwAvAgAAAA==.',
Yo='Yohh:BAABNQAECn8qAAICAAkKkxMaGgCKAQACAAkKkxMaGgCKAQAAAA==.Yorie:BAAANQADCgMIAwAAAA==.',
Yu='Yuriko:BAABNQAECn8vAAMeAAoK8A66DAAKAQAeAAkKTA+6DAAKAQAiAAEK4wXFFQAxAAAAAA==.',
Za='Zadory:BAAANQADCggIDAAAAA==.Zaidan:BAAANQADCggIDgAAAA==.',
Ze='Zendous:BAAANQAECgYIBgAAAA==.',
Zi='Zippitydooda:BAABNQAECn8XAAICAAcK3xstFQCrAQACAAcK3xstFQCrAQAAAA==.',
Zo='Zodiacc:BAABNQAECn8tAAIQAAoKSB9rBADNAQAQAAoKSB9rBADNAQAAAA==.Zornhealer:BAAANQADCggICAABNQAECgIIAgAMAAAAAA==.Zorrn:BAAANQAECgIIAgAAAA==.',
['Zí']='Zílch:BAAANQAECgEIAQAAAA==.',
['Zî']='Zîlch:BAAANQADCgcIBwAAAA==.',
['Zö']='Zölä:BAAANQAECgQIBwABNQAECgYIBwAMAAAAAA==.',
['Çh']='Çhrìs:BAAANQAECgQICAAAAA==.',
['Çú']='Çúrsè:BAAANQADCgIIAwAAAA==.',
['Èn']='Èntity:BAAANQAECgQIAgAAAA==.',
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
