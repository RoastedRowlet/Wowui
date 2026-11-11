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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Evoker-Devastation','Mage-Arcane','Druid-Balance','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Unknown-Unknown','Warlock-Demonology','Paladin-Holy','Monk-Brewmaster','Priest-Shadow','Shaman-Elemental','Shaman-Enhancement','Warlock-Affliction','Warlock-Destruction','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Druid-Restoration','Warrior-Arms','Monk-Windwalker','DemonHunter-Havoc','Paladin-Protection','Rogue-Subtlety','Mage-Fire','DemonHunter-Devourer','Druid-Feral','Druid-Guardian','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','DemonHunter-Vengeance','Monk-Mistweaver',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Ablestract:BAAANQADCgUIBQAAAA==.',
Ac='Acid:BAAANQAECgIIBAAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgYIDQAAAA==.',
Ak='Akamma:BAAANQAECgQICQAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliwings:BAAANQAECgYIEwAAAA==.',
Am='Amarokk:BAAANQAECgUICwAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
An='Ancestor:BAAANQADCggIFQAAAA==.Antumblare:BAAANQAECggIDQABNQAECgoKLQABAPghAA==.',
Ar='Arioch:BAAANQAECgYICQAAAA==.',
As='Ashireg:BAAANQAFFAMIAwAAAA==.Assassanz:BAAANQAECgIIAgAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgkJLgACAPkXAA==.',
Au='Auriyan:BAAANQADCgYIBgAAAA==.',
Az='Azimondius:BAABNQAECn8uAAIDAAoKChgJDQCSAgADAAoKChgJDQCSAgAAAA==.Azmora:BAAANQAECgUICQAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQAECgEIAQABNQAECgoKHAAEAEgIAA==.Belthora:BAAANQAECgQICQAAAA==.Benry:BAABNQAECn8aAAIFAAgKMRy+JgCeAgAFAAgKMRy+JgCeAgAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAAAAA==.Bistroboy:BAAANQAECggIAQAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgcIFwAAAA==.',
Br='Brianjany:BAAANQAECgQIBwAAAA==.Bristlebane:BAAANQAECgEIAQABNQAECgoKSwABAC0aAA==.Brook:BAAANQABCgEIAQAAAA==.Browntotem:BAAANQAECgcIDAAAAA==.',
Bu='Bubblehëarth:BAAANQAECgMIBgAAAA==.Bulgestomper:BAABNQAECn8iAAQGAAoKIhyXLACAAgAGAAoKIhyXLACAAgAHAAEKFAPCFAAoAAAIAAEKUwMDnQAiAAAAAA==.Bully:BAAANQAECgYICwAAAA==.Burbuja:BAAANQAECgYIDwAAAA==.Buschgore:BAAANQAECgEIBQAAAA==.',
['Bá']='Bádoink:BAAANQADCgcIBwAAAA==.',
Ca='Calimari:BAAANQADCggICAAAAA==.Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.Caste:BAAANQADCgcIDQABNQAECggILwAJAJUXAA==.Castr:BAAANQAECgQIBAABNQAECgIIBAAKAAAAAA==.',
Ce='Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Chargeantrot:BAAANQAECgEIAQABNQAECgcIFAALAGYaAA==.Cherrypalaid:BAABNQAECn8bAAMMAAkKcxYsQgBcAgAMAAkKcxYsQgBcAgABAAEKdAFp1gEaAAAAAA==.Chicntrl:BAABNQAECn8ZAAINAAcKqBoIDgAWAgANAAcKqBoIDgAWAgABNQAECgkJLQAOADYeAA==.',
Cl='Clingy:BAAANQAECgYIBgAAAA==.',
Co='Cobble:BAABNQAECn8lAAMPAAoKzA24RwCfAQAPAAoKzA24RwCfAQAQAAIKBAl2LQBtAAAAAA==.Colhap:BAABNQAECn8yAAIOAAoK1yAmCwAxAwAOAAoK1yAmCwAxAwAAAA==.Conjure:BAABNQAECn8jAAQRAAoKwBLBDABXAQALAAcKvBHBaACJAQARAAgK5hDBDABXAQASAAMKLBJZHQByAAAAAA==.Corbina:BAAANQAECggIAgAAAA==.Corehammer:BAAANQADCgYIDQAAAA==.',
Cr='Creamsocket:BAAANQAECgQJBgAAAA==.Cru:BAAANQAECgcIDgAAAA==.Crui:BAAANQADCggICAAAAA==.',
Cu='Culligan:BAABNQAECn9rAAMEAAoKRRtqNABmAgAEAAoKRRtqNABmAgATAAIKyg3aKgB2AAAAAA==.Cuttingcrew:BAAANQADCggICAAAAA==.',
Cy='Cygwin:BAABNQAECn8XAAMCAAkKeBnJXgDyAQACAAkKeBnJXgDyAQAPAAEKAADaOAExAAAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAABNQAECn8aAAMUAAkKgQr0ZgB1AQAUAAgKyQr0ZgB1AQAVAAIKhwcYnABaAAAAAA==.Datmage:BAAANQAECgEIAQAAAA==.',
De='Decomposed:BAAANQADCgMIAwAAAA==.Deigo:BAAANQADCggICAABNQAECgoKQAAPAOkfAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECggIDwAAAA==.Demunzz:BAAANQADCggIFgAAAA==.Destruction:BAABNQAECn8jAAIWAAgK7AVpbwA3AQAWAAgK7AVpbwA3AQAAAA==.Deylei:BAAANQAECgEIAgAAAA==.',
Di='Dithur:BAAANQADCgMIAwAAAA==.Divinespark:BAABNQAECn8jAAIXAAgK0xq+RwBPAgAXAAgK0xq+RwBPAgAAAA==.',
Do='Doinkbigs:BAABNQAECn8pAAILAAgKggw8mQCnAQALAAgKggw8mQCnAQAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Dooko:BAAANQAECgEIAQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAABNQAECn8UAAILAAcKZhokiAA4AQALAAcKZhokiAA4AQAAAA==.',
Dr='Draethno:BAAANQADCgUIBwAAAA==.Drambush:BAAANQADCgMIAwAAAA==.Draqulen:BAAANQAECgEIAQAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Drewsilla:BAAANQAECgQIBAAAAA==.Druidrose:BAABNQAECn8VAAMYAAcKNwarRQDTAAAYAAcKNwarRQDTAAAFAAEKMQI6xwAbAAAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAABNQAECn8UAAILAAkKOBjRYQAzAgALAAkKOBjRYQAzAgAAAA==.Dustbroom:BAAANQADCgQIBAAAAA==.',
['Dà']='Dàvë:BAAANQAECgQIBAABNQAECggILwAJAJUXAA==.',
Ea='Eap:BAAANQAECgEIAQAAAA==.Eazye:BAACNQAFFH8JAAIOAAMKSRqnDQCnAAAOAAMKSRqnDQCnAAA1AAQKf0gAAg4ACgrrIPsNAA4DAA4ACgrrIPsNAA4DAAAA.',
Ec='Ectojudge:BAAANQADCgUIBQAAAA==.',
Ed='Edgeffs:BAABNQAECn8jAAIZAAgKIAj6vQCCAQAZAAgKIAj6vQCCAQAAAA==.',
El='Elentiya:BAABNQAECn8gAAIXAAoKpRk4MACnAgAXAAoKpRk4MACnAgAAAA==.Elphs:BAABNQAECn8WAAIaAAoKdBciIAAtAgAaAAoKdBciIAAtAgAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQAECgQIBAAAAA==.',
Fa='Faarâm:BAAANQAECgMIAwAAAA==.',
Fe='Felorc:BAABNQAECn8YAAILAAYKzxA7vgBQAQALAAYKzxA7vgBQAQAAAA==.Fenton:BAABNQAECn8rAAIXAAoKvSJ/EgA0AwAXAAoKvSJ/EgA0AwAAAA==.Fentun:BAABNQAECn8cAAIMAAkKoiajCACDAwAMAAkKoiajCACDAwAAAA==.',
Fo='Foulplay:BAAANQAECgUIBQAAAA==.',
Fr='Free:BAAANQAECgEIAQAAAA==.',
Ga='Gabacadabra:BAAANQABCgIIAgAAAA==.Gali:BAAANQABCggIGQAAAA==.',
Ge='Gelektrael:BAABNQAECn8kAAMSAAgKOhJ7DQAhAgASAAgKOhJ7DQAhAgALAAUKGQdMDgGvAAAAAA==.Getchya:BAAANQAECgcIDAABNQAECggILwAJAJUXAA==.',
Gh='Ghoostt:BAABNQAECn8iAAIbAAkK3BUQJQDNAQAbAAkK3BUQJQDNAQABNQAFFAYIFQABAKAUAA==.Ghostzz:BAACNQAFFH8VAAIBAAYKoBShCQA1AQABAAYKoBShCQA1AQA1AAQKf08AAgEACgrLJIEPACgDAAEACgrLJIEPACgDAAAA.',
Gl='Gloríous:BAAANQAECgYIBwABNQAECgoKIgAYAI4VAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgABNQAECgEIAwAKAAAAAA==.',
Go='Goriath:BAAANQAECgUICwAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQAECgcIEAAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgYICwABNQAECgcIEgAKAAAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAAANQAECgcIEgAAAA==.Haldire:BAAANQABCgQIBAAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haruto:BAAANQADCggICAAAAA==.Haschel:BAAANQADCgcICgAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAABNQAECn8sAAIMAAgKGguWaQBlAQAMAAgKGguWaQBlAQAAAA==.Hoshi:BAAANQADCgQIBAABNQAECgkJLgAOAGIlAA==.',
Hu='Hurtak:BAAANQAECgYIDAAAAA==.',
Hy='Hycisan:BAABNQAECn8rAAIMAAoK8BumEQAhAwAMAAoK8BumEQAhAwAAAA==.Hysteria:BAABNQAECn8gAAMcAAgKEhXPIgBCAQAcAAYK6BvPIgBCAQABAAMK6AWyPwF9AAAAAA==.',
Ic='Icant:BAAANQAECgEIAQAAAA==.Icon:BAAANQADCgcICwAAAA==.Icydoodad:BAAANQAECggIDwABNQAECggILwAJAJUXAA==.',
Ik='Ikdutak:BAABNQAECn8cAAIEAAoKSAilfACfAQAEAAoKSAilfACfAQAAAA==.',
Il='Illusionwr:BAABNQAECn8XAAIZAAgKRBBbiwBXAQAZAAgKRBBbiwBXAQABNQAECgoKPwAbAHQgAA==.',
Ja='Jagerspell:BAABNQAECn9NAAMdAAoKbiSWBwA6AwAdAAoKxiOWBwA6AwAJAAQKfCS9TACOAQAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAABNQAECn8WAAIeAAkKzCXfAAAYAwAeAAkKzCXfAAAYAwAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAABNQAECn8fAAMQAAcKAQltIABYAQAQAAcKAQltIABYAQACAAMKpQE/BgFcAAAAAA==.Kanastra:BAABNQAECn8yAAIfAAoKgBdPEwAbAgAfAAoKgBdPEwAbAgABNQAECgoKLgADAAoYAA==.Karraa:BAAANQADCgYJBgABNQAECgcIHwAQAAEJAA==.Kaylib:BAABNQAECn8rAAIeAAkKNA87AwDTAQAeAAkKNA87AwDTAQAAAA==.',
Ke='Kesi:BAAANQAECgMIAwAAAA==.',
Kh='Khai:BAAANQAECgEIAQABNQAECgIIBAAKAAAAAA==.Khaztharion:BAABNQAECn8cAAIDAAkK6xLbCgClAQADAAkK6xLbCgClAQABNQAECgoKKwALAOsfAA==.Khaí:BAAANQAECgIIBAAAAA==.Khendrick:BAABNQAECn9LAAMBAAoKLRoITgAxAgABAAoKXhYITgAxAgAcAAgKjBVIJAC+AQAAAA==.',
Ki='Kinarra:BAAANQABCgYIBgAAAA==.Kittykatt:BAABNQAECn85AAIFAAoKnB2YEgB/AgAFAAoKnB2YEgB/AgAAAA==.',
Kn='Knowledge:BAABNQAECn8eAAIEAAgKviBDSgDtAgAEAAgKviBDSgDtAgAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECggIKQAZAPAXAA==.',
Kr='Kraggo:BAABNQAECn9DAAMLAAoK0B5sGQAhAwALAAoK0B5sGQAhAwASAAIKPA9dWQB0AAAAAA==.Krimzin:BAAANQAFFAEIAQABNQAFFAgIDwAGAPkXAA==.',
['Kí']='Kíllerwolf:BAAANQAECgUIDQAAAA==.',
La='Larsen:BAABNQAECn8lAAIPAAgKhBxCPQCBAgAPAAgKhBxCPQCBAgAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQAECgYICwAAAA==.',
Le='Leap:BAABNQAECn9BAAMgAAoKIhnzCQAkAgAgAAoK+BbzCQAkAgAhAAgK0RDZMAD6AAAAAA==.Legbah:BAAANQADCggIGAABNQAECggILwAJAJUXAA==.',
Li='Lightmare:BAAANQADCgYIBgAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lonesdove:BAAANQABCgIIAgAAAA==.Lookadragon:BAAANQAECgUIDQAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAQAKAAAAAA==.Lunacy:BAABNQAECn8fAAMBAAgKGgwNxwAxAQABAAgKsQkNxwAxAQAcAAQKbA4fQgCMAAAAAA==.',
Ly='Lynngosa:BAABNQAECn9BAAMiAAoKrhH3HAD8AQAiAAoKrhH3HAD8AQAjAAcKJA2TDgBdAQAAAA==.',
Ma='Maelidrael:BAAANQAECggIBwABNQAFFAMIBQATABwQAA==.Magebob:BAABNQAECn8eAAMEAAkKdQk3nQBXAQAEAAkKRgk3nQBXAQATAAIK6AhcPgAtAAAAAA==.Magisterium:BAABNQAECn8nAAIXAAoKNQsRUADjAQAXAAoKNQsRUADjAQAAAA==.Mario:BAAANQAECgEIAwAAAA==.Marlfox:BAAANQADCgEIAQAAAA==.Maulware:BAAANQADCgQICwAAAA==.',
Me='Meingaree:BAAANQABCgcICgAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.Metronome:BAAANQADCgEIAQAAAA==.',
Mi='Mightyguzz:BAABNQAECn8/AAIZAAoKxBKpbwBEAgAZAAoKxBKpbwBEAgAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAABNQAECn8UAAIhAAgKOBtBEABcAgAhAAgKOBtBEABcAgAAAA==.Minimuffn:BAABNQAECn8dAAMUAAgKiBm9QwAMAgAUAAcKgBy9QwAMAgAWAAIKtAvutwBYAAAAAA==.Misericordia:BAABNQAECn8wAAIOAAcKiA52KwASAQAOAAcKiA52KwASAQAAAA==.',
['Mø']='Møønchild:BAAANQAECgQIDAAAAA==.',
Na='Nadjia:BAAANQAECgEIAQAAAA==.Nafega:BAAANQADCgUICQAAAA==.Nanaish:BAAANQAECgYICQAAAA==.Naredionis:BAAANQADCgMIAwAAAA==.Natë:BAABNQAECn9AAAIkAAoKwBffDQBSAgAkAAoKwBffDQBSAgAAAA==.',
Ne='Nebakenazzer:BAAANQADCgQIBAABNQAECgQICQAKAAAAAA==.Necrotalon:BAAANQAECgYICAAAAA==.Nemesia:BAABNQAECn8pAAMZAAgK8BfYawCoAQAZAAgK8BfYawCoAQAlAAUKKBC1GAAVAQAAAA==.Neonsunrise:BAACNQAFFH8JAAIOAAMKSxodDgChAAAOAAMKSxodDgChAAA1AAQKf0cAAg4ACgqrIjgHAGcDAA4ACgqrIjgHAGcDAAAA.',
Nh='Nharuna:BAABNQAECn8sAAIGAAoKsg9agAAMAgAGAAoKsg9agAAMAgAAAA==.',
Ni='Nieloriel:BAABNQAECn8lAAIMAAoK4w8GPwAHAgAMAAoK4w8GPwAHAgAAAA==.Nimbus:BAABNQAECn8aAAMIAAoKjBTQJQAnAQAGAAkKQhSQkwByAQAIAAcKgQ/QJQAnAQABNQAFFAcIGwAPADwXAA==.Niykee:BAABNQAECn8mAAQJAAoKYyHSFgDGAgAJAAkK/B3SFgDGAgAmAAUKrBgZDgBcAQAdAAMKiSFwlADGAAAAAA==.',
No='Noboundss:BAABNQAECn8wAAMbAAoKYx1GHQCvAgAbAAoK5BxGHQCvAgAfAAUKLxfXPwBNAQAAAA==.Noztra:BAABNQAECn9CAAMTAAoKwQ1RFwARAQAEAAoKcAlaywDvAQATAAgKRg5RFwARAQAAAA==.',
Ns='Nsolant:BAAANQAECgYIDwAAAA==.',
Nu='Nubsy:BAAANQAECgEIAQAAAA==.Nuker:BAABNQAECn8ZAAIEAAYK1Atu3wDbAAAEAAYK1Atu3wDbAAAAAA==.Nukron:BAAANQAECgYICQAAAA==.',
Oh='Ohgr:BAABNQAECn8fAAMlAAcKJw6yFgD4AAAZAAcKzwdFzQBaAQAlAAYKUxCyFgD4AAAAAA==.Ohshifty:BAABNQAECn9eAAMFAAoK0hqfFQBYAgAFAAoK0hqfFQBYAgAYAAIK5gGIdQA1AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgYIDwAAAA==.',
Or='Orbsicles:BAABNQAECn8rAAMnAAoKJh2eDgBFAQAfAAoKFBo0IgA5AgAnAAcKyRqeDgBFAQAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQAECgUICQAAAA==.Papitomyrey:BAAANQAECgcIDAABNQAECgoKJAAcAL8hAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAACNQAFFH8KAAIUAAQKihroDAA+AQAUAAQKihroDAA+AQA1AAQKfz8AAxQACgp+JR4EALIDABQACgp+JR4EALIDABYAAgoAAOq7AAAAAAAA.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQABCgQIBQAAAA==.Pooter:BAABNQAECn8VAAIGAAgKUwUmCgHyAAAGAAgKUwUmCgHyAAAAAA==.Powpow:BAABNQAECn86AAIdAAoKwxm7IwBoAgAdAAoKwxm7IwBoAgAAAA==.',
Pr='Prejudice:BAABNQAECn8kAAIMAAgK4g4ydQC4AQAMAAgK4g4ydQC4AQAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAACNQAFFH8IAAIYAAMKswmjDQCwAAAYAAMKswmjDQCwAAA1AAQKf0AAAxgACgprD0omAKEBABgACgprD0omAKEBACAABwo8DcMYAHABAAAA.',
['Pû']='Pûff:BAABNQAECn8pAAIiAAkKGx7pDwCrAgAiAAkKGx7pDwCrAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQAECgMIAwAAAA==.Rainhoof:BAABNQAECn8kAAMgAAgKWBV3FgCTAQAgAAYKOhR3FgCTAQAYAAUK5An/SQDoAAAAAA==.Ralneth:BAACNQAFFH8jAAIiAAgKSRJjBAAzAgAiAAgKSRJjBAAzAgA1AAQKfzUAAiIACgpRGMoWAEsCACIACgpRGMoWAEsCAAAA.Randomtask:BAAANQADCggIEAAAAA==.Rapala:BAABNQAECn8eAAILAAgKwhl6awAbAgALAAgKwhl6awAbAgAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECggIHgALAMIZAA==.Raspútin:BAAANQAECgMIAwABNQAECggIEQAKAAAAAA==.Ravos:BAAANQABCgIIAgAAAA==.Rawdoinkers:BAAANQAECgQIBgAAAA==.Rawkfice:BAAANQADCggILQAAAA==.',
Re='Redlefbarg:BAAANQADCgQIBwAAAA==.Renakir:BAAANQADCgEIAQAAAA==.Renly:BAABNQAECn8hAAIcAAgKCRzCFQBRAgAcAAgKCRzCFQBRAgAAAA==.Restoral:BAAANQAECgEIAQAAAA==.',
Ri='Riordan:BAABNQAECn8iAAMGAAkKAiUlMADcAgAGAAkKAiUlMADcAgAIAAEKnx2MegBXAAAAAA==.Rivvetear:BAAANQADCgIIAgAAAA==.',
Rj='Rjolz:BAACNQAFFH8TAAQUAAcKNx86CwBaAQAUAAUK2CA6CwBaAQAWAAMKAxX7GgCGAAAVAAMKOxZFGQBcAAA1AAQKf2cABBQACgp3JuYCAMgDABQACgp3JuYCAMgDABYACgo9HxUMAMsCABUACQqDH+8aAGECAAAA.',
Ro='Roflchopr:BAABNQAECn8/AAIBAAoKDxVKcQDZAQABAAoKDxVKcQDZAQAAAA==.Roflkin:BAAANQAECgQIDgAAAA==.',
Sa='Sadcow:BAABNQAECn9AAAIPAAoK6R9zFgCqAgAPAAoK6R9zFgCqAgAAAA==.Sandalfon:BAAANQADCgYICQAAAA==.Sanleron:BAABNQAECn8jAAMcAAkKjht1DABVAgAcAAkK2xl1DABVAgABAAgK7RXYoADgAQAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIAwAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQAECgEIAQAAAA==.',
Sh='Sharayse:BAAANQAECgcICgAAAA==.Sharmee:BAABNQAECn8YAAICAAoKWQ/3egCbAQACAAoKWQ/3egCbAQAAAA==.Shiftycapone:BAABNQAECn8gAAIFAAoKzxWJHAAMAgAFAAoKzxWJHAAMAgAAAA==.Shmelverino:BAAANQAECgQIEAAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shockulater:BAAANQADCgEIAQAAAA==.Shogu:BAABNQAECn8pAAMZAAkKZwzsqgCyAQAZAAkKkArsqgCyAQAkAAEKDhNRQAA+AAAAAA==.Sháde:BAABNQAECn8VAAMRAAcKIw3LCwCqAQARAAcKIw3LCwCqAQASAAEKGgu+eAA1AAAAAA==.',
Si='Simpmother:BAEBNQAECn8qAAILAAoK8A86hADbAQALAAoK8A86hADbAQAAAA==.',
Sk='Skadie:BAAANQADCgYIBgABNQAECgoKQQAiAK4RAA==.',
Sl='Sladepriest:BAAANQAECgMIAwAAAA==.Slingablade:BAABNQAECn8+AAMfAAoKFBvGFgCqAgAfAAoKFBvGFgCqAgAnAAMKdQirJwBKAAAAAA==.',
Sm='Smallfoot:BAAANQADCgEIAQAAAA==.',
Sn='Sniffsniff:BAABNQAECn8WAAIMAAgKYCN6FgDzAgAMAAgKYCN6FgDzAgABNQAFFAgIGAACADolAA==.',
So='Solvi:BAAANQAECgUICgAAAA==.Sonira:BAAANQADCgEIAQAAAA==.Sorá:BAABNQAECn81AAIZAAoK2yJhEgAEAwAZAAoK2yJhEgAEAwABNQAECgoKOQAWAPAXAA==.Soulbrand:BAAANQAECgMIBQAAAA==.',
Sp='Spellz:BAAANQADCgcIDAABNQAECgYIDQAKAAAAAA==.',
St='Stabathuh:BAABNQAECn8vAAMJAAgKlRdiFACDAQAdAAgK2BEJRADVAQAJAAgKqhRiFACDAQAAAA==.Stabnskullz:BAAANQAECgQJBAABNQAECggIDwAKAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIIAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECggILwAJAJUXAA==.Stoopidlock:BAAANQADCggIGwABNQAECggILwAJAJUXAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECggILwAJAJUXAA==.Stoopidrood:BAAANQAECgQIBQABNQAECggILwAJAJUXAA==.Stoopidtroll:BAAANQADCgEIAQABNQAECggILwAJAJUXAA==.Stoopidwarur:BAABNQAECn8XAAIlAAgKsBwxBgBRAgAlAAgKsBwxBgBRAgABNQAECggILwAJAJUXAA==.Stormclaw:BAABNQAECn8iAAInAAgKMgqyFwA0AQAnAAgKMgqyFwA0AQAAAA==.Styne:BAAANQAECgMIAwABNQAECgoKQAAPAOkfAA==.',
Su='Sufiya:BAABNQAECn8aAAIGAAkKxQanrACrAQAGAAkKxQanrACrAQAAAA==.Suki:BAABNQAECn89AAIoAAoKryA6BgA3AwAoAAoKryA6BgA3AwAAAA==.Sulfion:BAAANQAECgYIDQAAAA==.Sumig:BAAANQAECgEIAQAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYIEAAAAA==.',
Sy='Sylveria:BAAANQAECgIIAwAAAA==.Sylvershadow:BAABNQAECn8cAAIGAAcKyghquQAkAQAGAAcKyghquQAkAQAAAA==.Syphon:BAABNQAECn9RAAMnAAoKiSSoAQCKAwAnAAoKiSSoAQCKAwAbAAQK+AbNdwBBAAAAAA==.',
['Sý']='Sýrin:BAAANQADCggJCgAAAA==.',
Ta='Tandarilada:BAAANQAECgEIAQAAAA==.Tanfer:BAAANQAECgEIAQAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECn8qAAIZAAoKGBtSbQBKAgAZAAoKGBtSbQBKAgAAAA==.Thndrstrmlol:BAAANQAECgMIAwAAAA==.',
Ti='Titanic:BAAANQAECgUICAAAAA==.',
To='Tomcruise:BAABNQAECn8qAAIBAAoK3R2lWwCFAgABAAoK3R2lWwCFAgAAAA==.Totemlyawsum:BAAANQAECgYICwAAAA==.',
Tr='True:BAAANQAECgQIBgAAAA==.',
Tw='Twotone:BAAANQADCgcICAAAAA==.',
Ul='Ulkthar:BAAANQAECgUIBgABNQAFFAUICwAEAFUKAA==.Ultrauchuva:BAAANQAECgEIAQAAAA==.',
Un='Unholyhammer:BAAANQABCgMIAQABNQAECggIDwAKAAAAAA==.',
Va='Vacunamatata:BAAANQAECgUIEAAAAA==.Vaiyrnlol:BAACNQAFFH8LAAICAAQKMhV9EQAoAQACAAQKMhV9EQAoAQA1AAQKfzIAAwIACgqRHWIhAOMCAAIACgqRHWIhAOMCAA8ACApYH8wwAAACAAAA.Vanlin:BAABNQAECn8fAAIYAAgKHBt0GwBcAgAYAAgKHBt0GwBcAgAAAA==.',
Ve='Vexxdr:BAABNQAECn9IAAMYAAoK6xU/FgBSAgAYAAoK6xU/FgBSAgAFAAkK1RY7LACJAQABNQAECgoKTgACALcjAA==.Vexxs:BAABNQAECn9OAAMCAAoKtyObBQC0AwACAAoKtyObBQC0AwAPAAgKuBg4QAC8AQAAAA==.',
Vo='Voidsuzu:BAABNQAECn9AAAMfAAoKYxZIHQBqAgAfAAoKYxZIHQBqAgAnAAMKiQsqIAB1AAAAAA==.Vormedicus:BAAANQAECggIEQAAAA==.',
Vs='Vsaguzz:BAAANQAECgEIAQABNQAECgoKPwAZAMQSAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQICQAAAA==.',
Wa='Waroo:BAAANQADCggICAAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Wickïdus:BAAANQABCggIEAAAAA==.Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECgYIDwAAAA==.',
Xa='Xaphelion:BAAANQAECgEIAQAAAA==.Xazio:BAABNQAECn87AAIcAAoKoxmyDgArAgAcAAoKoxmyDgArAgAAAA==.',
Yi='Yiang:BAABNQAECn8WAAIaAAcKChujJQD2AQAaAAcKChujJQD2AQAAAA==.Yiav:BAAANQAECgIIAwABNQAFFAQICwACADIVAA==.',
Yl='Ylndrysa:BAABNQAECn9lAAMYAAoK+xrjFgBJAgAYAAoK+xrjFgBJAgAFAAQKXAroUADIAAAAAA==.',
Ze='Zedrock:BAACNQAFFH8FAAITAAMKHBCpBwCRAAATAAMKHBCpBwCRAAA1AAQKf0EAAxMACgpwI3MCAOsCABMACgpwI3MCAOsCAAQAAgpbC1hRATcAAAAA.Zeezu:BAAANQAECgMIAwAAAA==.Zekodian:BAAANQADCgQIBAAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAABNQAECn8YAAMXAAkK1Qc1qQAaAQAXAAkK1Qc1qQAaAQAOAAgK+wIXSAB3AAAAAA==.Zhitolight:BAAANQAECgQIEQABNQAFFAYICAAXAJcSAA==.',
Zu='Zuro:BAABNQAECn8dAAIGAAgK1QcTwACDAQAGAAgK1QcTwACDAQAAAA==.',
['Ðø']='Ðønsý:BAAANQADCgEIAQAAAA==.',
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
