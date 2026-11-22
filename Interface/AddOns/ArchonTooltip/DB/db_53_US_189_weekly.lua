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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Evoker-Devastation','Mage-Arcane','Druid-Balance','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Unknown-Unknown','Warlock-Demonology','Paladin-Holy','Monk-Brewmaster','Priest-Shadow','Shaman-Elemental','Shaman-Enhancement','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Warrior-Arms','Monk-Windwalker','Rogue-Assassination','DemonHunter-Havoc','Paladin-Protection','Rogue-Subtlety','Mage-Fire','DemonHunter-Devourer','Druid-Feral','Druid-Guardian','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Rogue-Outlaw','DemonHunter-Vengeance','Monk-Mistweaver',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Ablestract:BAAANQADCgUIBQAAAA==.',
Ac='Acid:BAAANQAECgIIBAAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgcIDAAAAA==.',
Ak='Akamma:BAAANQAECgQICAAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIGAAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliwings:BAAANQAECgYIEwAAAA==.',
Am='Amarokk:BAAANQAECgUICwAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
An='Ancestor:BAAANQADCggIFQAAAA==.Antumblare:BAAANQAECggICwABNQAECgoKLgABAPghAA==.',
Ar='Arioch:BAAANQAECgYICQAAAA==.',
As='Ashireg:BAAANQAFFAMIAwAAAA==.Assassanz:BAAANQAECgIIAgAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgkJLgACAPkXAA==.',
Au='Auriyan:BAAANQADCgYIBgAAAA==.',
Az='Azimondius:BAABNQAECn80AAIDAAoKlxpqCAD8AQADAAoKlxpqCAD8AQAAAA==.Azmora:BAAANQAECgUICAAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQADCgYIBwABNQAECgoKHAAEAEgIAA==.Belthora:BAAANQAECgQICQAAAA==.Benry:BAABNQAECn8aAAIFAAgKMRy+JgCeAgAFAAgKMRy+JgCeAgAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAAAAA==.Bistroboy:BAAANQAECggIAQAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgcIFwAAAA==.',
Br='Brianjany:BAAANQAECgQIBwAAAA==.Bristlebane:BAAANQAECgEIAQABNQAECgoKUgABABEcAA==.Brook:BAAANQABCgMIAwAAAA==.Browntotem:BAAANQAECgcIBgAAAA==.',
Bu='Bubblehëarth:BAAANQAECgMIBgAAAA==.Bulgestomper:BAABNQAECn8iAAQGAAoKIhw3MwB6AgAGAAoKIhw3MwB6AgAHAAEKFAPCFAAoAAAIAAEKUwMDnQAiAAAAAA==.Bully:BAAANQAECgYICwAAAA==.Burbuja:BAAANQAECggIEAAAAA==.Buschgore:BAAANQAECgIIAgAAAA==.',
['Bá']='Bádoink:BAAANQADCgcIBwAAAA==.',
Ca='Calimari:BAAANQADCggICAAAAA==.Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.Caste:BAAANQADCgcIDQABNQAECggIHQAJAAcfAA==.Castr:BAAANQAECgQIBAABNQAECgIIBAAKAAAAAA==.',
Ce='Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Chargeantrot:BAAANQAECgEIAQABNQAECgcIFAALAGYaAA==.Cherrypalaid:BAABNQAECn8bAAMMAAkKcxYsQgBcAgAMAAkKcxYsQgBcAgABAAEKdAFp1gEaAAAAAA==.Chicntrl:BAABNQAECn8ZAAINAAcKqBoIDgAWAgANAAcKqBoIDgAWAgABNQAFFAQIBwAOAFUQAA==.',
Cl='Clingy:BAAANQAECgcIBgAAAA==.',
Co='Cobble:BAABNQAECn8lAAMPAAoKzA2STgCdAQAPAAoKzA2STgCdAQAQAAIKBAkzMABtAAAAAA==.Colhap:BAABNQAECn8yAAIOAAoK1yAmCwAxAwAOAAoK1yAmCwAxAwAAAA==.Conjure:BAABNQAECn8jAAQRAAoKwBIqDgBUAQALAAcKvBGVcQCGAQARAAgK5hAqDgBUAQASAAMKLBLbHwBwAAAAAA==.Corbina:BAAANQAECggIAgAAAA==.Corehammer:BAAANQADCgYIDQAAAA==.',
Cr='Crazykiller:BAAANQAECgUIBQABNQAECgoKMgATABQMAA==.Creamsocket:BAAANQAECgQJBgAAAA==.Cru:BAAANQAECgcIDAAAAA==.Crui:BAAANQADCggICAAAAA==.',
Cu='Culligan:BAABNQAECn9yAAMEAAoKpBsNOABmAgAEAAoKpBsNOABmAgAUAAIKyg0KLgB2AAAAAA==.Cuttingcrew:BAAANQADCggICAAAAA==.',
Cy='Cygwin:BAABNQAECn8YAAMCAAkKzxnJXgDyAQACAAkKzxnJXgDyAQAPAAEKAADaOAExAAAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAABNQAECn8aAAMVAAkKgQr0ZgB1AQAVAAgKyQr0ZgB1AQAWAAIKhwcYnABaAAAAAA==.Datmage:BAAANQAECgEIAQAAAA==.',
De='Decomposed:BAAANQADCgMIAwAAAA==.Deigo:BAAANQADCggICAABNQAECgoKRAAPAAkgAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECggIDwAAAA==.Demunzz:BAAANQADCggIFgAAAA==.Destruction:BAABNQAECn8kAAIXAAkKmAZpbwA3AQAXAAkKmAZpbwA3AQAAAA==.Deylei:BAAANQAECgEIAQAAAA==.',
Di='Dithur:BAAANQADCgMIAwAAAA==.Divinespark:BAABNQAECn8kAAITAAkKnBu+RwBPAgATAAkKnBu+RwBPAgAAAA==.',
Do='Doinkbigs:BAABNQAECn8pAAILAAgKggw8mQCnAQALAAgKggw8mQCnAQAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Dooko:BAAANQAECgEIAQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAABNQAECn8UAAILAAcKZho5kwA0AQALAAcKZho5kwA0AQAAAA==.',
Dr='Draethno:BAAANQADCgUIBwAAAA==.Drambush:BAAANQADCgMIAwAAAA==.Draqulen:BAAANQADCgEIAQAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Drewsilla:BAAANQAECgQICAAAAA==.Druidrose:BAABNQAECn8VAAMYAAcKNwaWSgDTAAAYAAcKNwaWSgDTAAAFAAEKMQI6xwAbAAAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAABNQAECn8UAAILAAkKOBjRYQAzAgALAAkKOBjRYQAzAgAAAA==.Dustbroom:BAAANQADCgQIBAAAAA==.',
['Dà']='Dàvë:BAAANQAECgQIBAABNQAECggIHQAJAAcfAA==.',
Ea='Eazye:BAACNQAFFH8JAAIOAAMKSRpfDwClAAAOAAMKSRpfDwClAAA1AAQKf0gAAg4ACgrrIPsNAA4DAA4ACgrrIPsNAA4DAAAA.',
Ec='Ectojudge:BAAANQADCgUIBQAAAA==.',
Ed='Edgeffs:BAABNQAECn8kAAIZAAkKFAj6vQCCAQAZAAkKFAj6vQCCAQAAAA==.',
El='Elentiya:BAABNQAECn8gAAITAAoKpRk4MACnAgATAAoKpRk4MACnAgAAAA==.Elphs:BAABNQAECn8WAAIaAAoKdBciIAAtAgAaAAoKdBciIAAtAgAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Erayedael:BAAANQADCgQIBAAAAA==.Eriius:BAAANQAECgUIBAAAAA==.',
Fa='Faarâm:BAAANQAECgMIAgAAAA==.',
Fe='Felorc:BAABNQAECn8YAAILAAYKzxA7vgBQAQALAAYKzxA7vgBQAQAAAA==.Fenton:BAABNQAECn8rAAITAAoKvSIUFQAuAwATAAoKvSIUFQAuAwAAAA==.Fentun:BAABNQAECn8cAAIMAAkKoiajCACDAwAMAAkKoiajCACDAwAAAA==.',
Fo='Foulplay:BAAANQAECgUIBQAAAA==.',
Fr='Free:BAAANQAECgEIAQAAAA==.',
Ga='Gabacadabra:BAAANQABCgIIAgAAAA==.Gali:BAAANQABCggIGQAAAA==.',
Ge='Gelektrael:BAABNQAECn8lAAMSAAkKHxF7DQAhAgASAAgKOhJ7DQAhAgALAAYKxgd05QCHAAAAAA==.Getchya:BAABNQAECn8WAAIbAAkK6xZMCgA1AgAbAAkK6xZMCgA1AgABNQAECggIHQAJAAcfAA==.',
Gh='Ghoostt:BAABNQAECn8iAAIcAAkK3BVoKADKAQAcAAkK3BVoKADKAQABNQAFFAYIFgABAKAUAA==.Ghostzz:BAACNQAFFH8WAAIBAAYKoBTOCwAvAQABAAYKoBTOCwAvAQA1AAQKf1EAAgEACgrLJBsSAB4DAAEACgrLJBsSAB4DAAAA.',
Gl='Gloríous:BAAANQAECgYIDAABNQAECgoKIgAYAI4VAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgABNQAECgEIAQAKAAAAAA==.',
Go='Goriath:BAAANQAECgUICQAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAABNQAECn8UAAIGAAgKKg+9wgAsAQAGAAgKKg+9wgAsAQAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgYICwABNQAECgcIEgAKAAAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAAANQAECgcIEgAAAA==.Haldire:BAAANQABCgQIBAAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haruto:BAAANQADCggICAAAAA==.Haschel:BAAANQADCgcICgAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAABNQAECn8sAAIMAAgKGgvZcwBZAQAMAAgKGgvZcwBZAQAAAA==.Hoshi:BAAANQADCgQIBAABNQAECgkJLgAOAGIlAA==.',
Hu='Hurtak:BAAANQAECggIDQAAAA==.',
Hy='Hycisan:BAABNQAECn8rAAIMAAoK8BtvFAAWAwAMAAoK8BtvFAAWAwAAAA==.Hysteria:BAABNQAECn8nAAMdAAkKlRgTFQDeAQAdAAgKdBsTFQDeAQABAAMK6AUJUAF7AAAAAA==.',
Ic='Icon:BAAANQADCgcICwAAAA==.Icydoodad:BAAANQAECggIDwABNQAECggIHQAJAAcfAA==.',
Ik='Ikdutak:BAABNQAECn8cAAIEAAoKSAgjhQCeAQAEAAoKSAgjhQCeAQAAAA==.',
Il='Illusionwr:BAABNQAECn8XAAIZAAgKRBBJlQBWAQAZAAgKRBBJlQBWAQABNQAECgoKPwAcAHQgAA==.',
Ja='Jagerspell:BAABNQAECn9PAAMeAAoKbiQuCAA5AwAeAAoKxiMuCAA5AwAbAAQKfCS9TACOAQAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAABNQAECn8WAAIfAAkKzCXfAAAYAwAfAAkKzCXfAAAYAwAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAABNQAECn8iAAMQAAkKPgooIAAjAQAQAAgK6wgoIAAjAQACAAQKNQI/BgFcAAAAAA==.Kanastra:BAABNQAECn82AAIgAAoKuhcUFAAiAgAgAAoKuhcUFAAiAgABNQAECgoKNAADAJcaAA==.Karraa:BAAANQADCgYJBgABNQAECgkJIgAQAD4KAA==.Kaylib:BAABNQAECn8rAAIfAAkKNA87AwDTAQAfAAkKNA87AwDTAQAAAA==.',
Ke='Kesi:BAAANQAECgMIAwAAAA==.',
Kh='Khaztharion:BAABNQAECn8cAAIDAAkK6xKoCwCkAQADAAkK6xKoCwCkAQABNQAECgoKLwALAOsfAA==.Khaí:BAAANQAECgIIAQAAAA==.Khendrick:BAABNQAECn9SAAMBAAoKERyTOgB8AgABAAoK+xqTOgB8AgAdAAoKexNIJAC+AQAAAA==.',
Ki='Kinarra:BAAANQABCgYIBgAAAA==.Kittykatt:BAABNQAECn85AAIFAAoKnB32EwB9AgAFAAoKnB32EwB9AgAAAA==.',
Kn='Knowledge:BAABNQAECn8eAAIEAAgKviBDSgDtAgAEAAgKviBDSgDtAgAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECggIKQAZAPAXAA==.',
Kr='Kraggo:BAABNQAECn9DAAMLAAoK0B5sGQAhAwALAAoK0B5sGQAhAwASAAIKPA9dWQB0AAAAAA==.Krimzin:BAAANQAFFAEIAQABNQAFFAgIDwAGAPkXAA==.',
['Kí']='Kíllerwolf:BAAANQAECgYIDgAAAA==.',
La='Larsen:BAABNQAECn8mAAIPAAkK+hxCPQCBAgAPAAkK+hxCPQCBAgAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQAECgYICgAAAA==.',
Le='Leap:BAABNQAECn9DAAMhAAoKIhliCwAgAgAhAAoK+BZiCwAgAgAiAAgK0RA5NQD3AAAAAA==.Legbah:BAAANQADCggIGAABNQAECggIHQAJAAcfAA==.',
Li='Lightmare:BAAANQADCgYIBgAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lonesdove:BAAANQABCgIIAgAAAA==.Lookadragon:BAAANQAECgUIDQAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAQAKAAAAAA==.Lunacy:BAABNQAECn8mAAMBAAoKBgsooQCLAQABAAoKNwkooQCLAQAdAAQKbA5pRgCMAAAAAA==.',
Ly='Lynngosa:BAABNQAECn9BAAMjAAoKrhH3HAD8AQAjAAoKrhH3HAD8AQAkAAcKJA2TDgBdAQAAAA==.',
Ma='Maelidrael:BAAANQAECggICgABNQAFFAQICAAUADMPAA==.Magebob:BAABNQAECn8fAAMEAAkKkwr0nQBpAQAEAAkKZQr0nQBpAQAUAAIK6AikQgAtAAAAAA==.Magisterium:BAABNQAECn8yAAITAAoKFAyPVQDmAQATAAoKFAyPVQDmAQAAAA==.Mario:BAAANQAECgEIAQAAAA==.Marlfox:BAAANQADCgEIAQAAAA==.Maulware:BAAANQADCgQICwAAAA==.',
Me='Meingaree:BAAANQABCgcICgAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.Metronome:BAAANQADCgEIAgAAAA==.',
Mi='Mightyguzz:BAABNQAECn9DAAIZAAoKxBKpbwBEAgAZAAoKxBKpbwBEAgAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAABNQAECn8UAAIiAAgKOBtBEABcAgAiAAgKOBtBEABcAgAAAA==.Minimuffn:BAABNQAECn8dAAMVAAgKiBm9QwAMAgAVAAcKgBy9QwAMAgAXAAIKtAvutwBYAAAAAA==.Misericordia:BAABNQAECn82AAIOAAcKiA5INwBqAQAOAAcKiA5INwBqAQAAAA==.',
['Mø']='Møønchild:BAAANQAECgQICgAAAA==.',
Na='Nafega:BAAANQADCgUIDAAAAA==.Nanaish:BAAANQAECgYICQAAAA==.Naredionis:BAAANQADCgMIBAAAAA==.Natë:BAABNQAECn9AAAIlAAoKwBffDQBSAgAlAAoKwBffDQBSAgAAAA==.',
Ne='Nebakenazzer:BAAANQADCgQIBQABNQAECgQICAAKAAAAAA==.Necrotalon:BAAANQAECgYIBwAAAA==.Nemesia:BAABNQAECn8pAAMZAAgK8BeqdAClAQAZAAgK8BeqdAClAQAJAAUKKBC1GAAVAQAAAA==.Neonsunrise:BAACNQAFFH8JAAIOAAMKSxq9DwChAAAOAAMKSxq9DwChAAA1AAQKf0cAAg4ACgqrIjgHAGcDAA4ACgqrIjgHAGcDAAAA.',
Nh='Nharuna:BAABNQAECn8sAAIGAAoKsg9agAAMAgAGAAoKsg9agAAMAgAAAA==.',
Ni='Nieloriel:BAABNQAECn8lAAIMAAoK4w9MRQD/AQAMAAoK4w9MRQD/AQAAAA==.Nimbus:BAABNQAECn8aAAMIAAoKjBRmKAAmAQAGAAkKQhRLoQBxAQAIAAcKgQ9mKAAmAQABNQAFFAcIGwAPADwXAA==.Niykee:BAABNQAECn8mAAQbAAoKYyHSFgDGAgAbAAkK/B3SFgDGAgAmAAUKrBgZDgBcAQAeAAMKiSHEnwDGAAAAAA==.',
No='Noboundss:BAABNQAECn8wAAMcAAoKYx1GHQCvAgAcAAoK5BxGHQCvAgAgAAUKLxfXPwBNAQAAAA==.Noztra:BAABNQAECn9KAAMUAAoKWA6wGQARAQAEAAoKDApaywDvAQAUAAgKRg6wGQARAQAAAA==.',
Ns='Nsolant:BAAANQAECgYIDgAAAA==.',
Nu='Nubsy:BAAANQAECgEIAQAAAA==.Nuker:BAABNQAECn8ZAAIEAAYK1Au96QDaAAAEAAYK1Au96QDaAAAAAA==.Nukron:BAAANQAECgYIBgAAAA==.',
Oh='Ohgr:BAABNQAECn8fAAMJAAcKJw4CGQD2AAAZAAcKzwdFzQBaAQAJAAYKUxACGQD2AAAAAA==.Ohshifty:BAABNQAECn9eAAMFAAoK0hpRFwBXAgAFAAoK0hpRFwBXAgAYAAIK5gGIdQA1AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgYIDwAAAA==.',
Or='Orangey:BAAANQADCgEIAgAAAA==.Orbsicles:BAABNQAECn8rAAMnAAoKJh0gEABEAQAgAAoKFBo0IgA5AgAnAAcKyRogEABEAQAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQAECgQIBgAAAA==.Papitomyrey:BAAANQAECgcIDAABNQAECgoKJAAdAL8hAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAACNQAFFH8KAAIVAAQKihroDAA+AQAVAAQKihroDAA+AQA1AAQKfz8AAxUACgp+JR4EALIDABUACgp+JR4EALIDABcAAgoAAFfDAAAAAAAA.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQABCgQIBQAAAA==.Pooter:BAABNQAECn8VAAIGAAgKUwUmCgHyAAAGAAgKUwUmCgHyAAAAAA==.Powpow:BAABNQAECn8+AAIeAAoKwxkwJwBmAgAeAAoKwxkwJwBmAgAAAA==.',
Pr='Prejudice:BAABNQAECn8lAAIMAAkKjQ8ydQC4AQAMAAkKjQ8ydQC4AQAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAACNQAFFH8IAAIYAAMKswkdDwCwAAAYAAMKswkdDwCwAAA1AAQKf0EAAxgACgprD9kpAKEBABgACgprD9kpAKEBACEABwo8DcMYAHABAAAA.',
['Pû']='Pûff:BAABNQAECn8pAAIjAAkKGx7pDwCrAgAjAAkKGx7pDwCrAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQAECgMIAwAAAA==.Rainhoof:BAABNQAECn8lAAMhAAkKFBV3FgCTAQAhAAcKFBR3FgCTAQAYAAUK5An/SQDoAAAAAA==.Ralneth:BAACNQAFFH8jAAIjAAgKSRJjBAAzAgAjAAgKSRJjBAAzAgA1AAQKfzUAAiMACgpRGMoWAEsCACMACgpRGMoWAEsCAAAA.Randomtask:BAAANQADCggIEQAAAA==.Rapala:BAABNQAECn8eAAILAAgKwhl6awAbAgALAAgKwhl6awAbAgAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECggIHgALAMIZAA==.Raspútin:BAAANQAECgMIAwABNQAECggIDgAKAAAAAA==.Ravos:BAAANQABCgIIAgAAAA==.Rawdoinkers:BAAANQAECgQIBgAAAA==.Rawkfice:BAAANQADCggILQAAAA==.',
Re='Redlefbarg:BAAANQADCgQIBwAAAA==.Renakir:BAAANQADCgEIAQAAAA==.Renly:BAABNQAECn8jAAIdAAoKqxrCFQBRAgAdAAoKqxrCFQBRAgAAAA==.Restoral:BAAANQAECgEIAQAAAA==.',
Ri='Riordan:BAABNQAECn8iAAMGAAkKAiUlMADcAgAGAAkKAiUlMADcAgAIAAEKnx2MegBXAAAAAA==.Rivvetear:BAAANQADCgIIAgAAAA==.',
Rj='Rjolz:BAACNQAFFH8TAAQVAAcKNx86CwBaAQAVAAUK2CA6CwBaAQAXAAMKAxUWHgCDAAAWAAMKOxacGwBcAAA1AAQKf2cABBUACgp3JuYCAMgDABUACgp3JuYCAMgDABcACgo9Hx8NAMQCABYACQqDH2ceAFcCAAAA.',
Ro='Roflchopr:BAABNQAECn9IAAIBAAoKNhX9XQAYAgABAAoKNhX9XQAYAgAAAA==.Roflkin:BAAANQAECggIEAAAAA==.',
Sa='Sadcow:BAABNQAECn9EAAIPAAoKCSAKGACqAgAPAAoKCSAKGACqAgAAAA==.Sandalfon:BAAANQADCgYICQAAAA==.Sanleron:BAABNQAECn8kAAMdAAkKjhvLDQBQAgAdAAkK2xnLDQBQAgABAAgKARbYoADgAQAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIAwAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQAECgEIAQAAAA==.',
Sh='Sharayse:BAAANQAECgcIBwAAAA==.Sharmee:BAABNQAECn8YAAICAAoKWQ/3egCbAQACAAoKWQ/3egCbAQAAAA==.Shiftycapone:BAABNQAECn8gAAIFAAoKzxXKHgAKAgAFAAoKzxXKHgAKAgAAAA==.Shmelverino:BAAANQAECgQIDwAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shockulater:BAAANQADCgEIAgAAAA==.Shogu:BAABNQAECn8qAAMZAAkKywzsqgCyAQAZAAkK9ArsqgCyAQAlAAEKDhNRQAA+AAAAAA==.Sháde:BAABNQAECn8VAAMRAAcKIw3LCwCqAQARAAcKIw3LCwCqAQASAAEKGgu+eAA1AAAAAA==.',
Si='Simpmother:BAEBNQAECn8qAAILAAoK8A86hADbAQALAAoK8A86hADbAQAAAA==.',
Sk='Skadie:BAAANQADCgYIBgABNQAECgoKQQAjAK4RAA==.',
Sl='Sladepriest:BAAANQAECgMIAwAAAA==.Slingablade:BAABNQAECn8+AAMgAAoKFBvGFgCqAgAgAAoKFBvGFgCqAgAnAAMKdQhSKgBKAAAAAA==.',
Sm='Smallfoot:BAAANQADCgEIAQAAAA==.',
Sn='Sniffsniff:BAABNQAECn8WAAIMAAgKYCNFGQDtAgAMAAgKYCNFGQDtAgABNQAFFAgIGAACADolAA==.',
So='Solvi:BAAANQAECgUICgAAAA==.Sonira:BAAANQADCgEIAgAAAA==.Sorá:BAABNQAECn81AAIZAAoK2yK5FAD+AgAZAAoK2yK5FAD+AgABNQAECgoKOQAXAPAXAA==.Soulbrand:BAAANQAECgMIBQAAAA==.',
Sp='Spellz:BAAANQADCgcIDAABNQAECgYICgAKAAAAAA==.',
St='Stabathuh:BAABNQAECn8zAAMbAAkKRBn9DAD8AQAbAAkKthb9DAD8AQAeAAgK2BFJSwDUAQABNQAECggIHQAJAAcfAA==.Stabnskullz:BAAANQAECgQJBAABNQAECggIDwAKAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIIAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECggIHQAJAAcfAA==.Stoopidlock:BAAANQADCggIGwABNQAECggIHQAJAAcfAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECggIHQAJAAcfAA==.Stoopidrood:BAAANQAECgQIBQABNQAECggIHQAJAAcfAA==.Stoopidtroll:BAAANQADCgEIAQABNQAECggIHQAJAAcfAA==.Stoopidwarur:BAABNQAECn8dAAIJAAgKBx/HBQB0AgAJAAgKBx/HBQB0AgAAAA==.Stormclaw:BAABNQAECn8jAAInAAkKIgqyFwA0AQAnAAkKIgqyFwA0AQAAAA==.Styne:BAAANQAECgMIAwABNQAECgoKRAAPAAkgAA==.',
Su='Sufiya:BAABNQAECn8aAAIGAAkKxQanrACrAQAGAAkKxQanrACrAQAAAA==.Suki:BAABNQAECn89AAIoAAoKryA6BgA3AwAoAAoKryA6BgA3AwAAAA==.Sulfion:BAAANQAECgYICgAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYIEAAAAA==.',
Sy='Sylveria:BAAANQAECgIIAwAAAA==.Sylvershadow:BAABNQAECn8dAAIGAAcKygiPxwAiAQAGAAcKygiPxwAiAQAAAA==.Syphon:BAABNQAECn9RAAMnAAoKiSSoAQCKAwAnAAoKiSSoAQCKAwAcAAQK+AZtfwA+AAAAAA==.',
['Sý']='Sýrin:BAAANQADCggJCgAAAA==.',
Ta='Tandarilada:BAAANQAECgEIAQAAAA==.Tanfer:BAAANQAECgEIAQAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECn8qAAIZAAoKGBtSbQBKAgAZAAoKGBtSbQBKAgAAAA==.Thndrstrmlol:BAAANQAECgMIAwAAAA==.',
Ti='Titanic:BAAANQAECgUIBgAAAA==.',
To='Tomcruise:BAABNQAECn8qAAIBAAoK3R2lWwCFAgABAAoK3R2lWwCFAgAAAA==.Totemlyawsum:BAAANQAECgYICwAAAA==.',
Tr='True:BAAANQAECgQIBgAAAA==.',
Tw='Twotone:BAAANQADCgcICAAAAA==.',
Ul='Ulkthar:BAAANQAECgUIBQABNQAFFAUICwAEAFUKAA==.',
Un='Unholyhammer:BAAANQABCgMIAQABNQAECggIDwAKAAAAAA==.',
Va='Vacunamatata:BAABNQAECn8WAAIdAAgKnRRDGQCqAQAdAAgKnRRDGQCqAQAAAA==.Vaiyrnlol:BAACNQAFFH8LAAICAAQKMhW4EwAnAQACAAQKMhW4EwAnAQA1AAQKfzIAAwIACgqRHWIhAOMCAAIACgqRHWIhAOMCAA8ACApYHzM2APwBAAAA.Vanlin:BAABNQAECn8fAAIYAAgKHBt0GwBcAgAYAAgKHBt0GwBcAgAAAA==.',
Ve='Vexxdr:BAABNQAECn9LAAMYAAoKGhiSEwCRAgAYAAoKGhiSEwCRAgAFAAkKXRfjLgCOAQAAAA==.Vexxs:BAABNQAECn9TAAMCAAoKMyRvBQDDAwACAAoKMyRvBQDDAwAPAAgKwBh0RgC7AQABNQAECgoKSwAYABoYAA==.',
Vo='Voidsuzu:BAABNQAECn9EAAMgAAoKYxZIHQBqAgAgAAoKYxZIHQBqAgAnAAMKiQuCIgB1AAAAAA==.Vormedicus:BAAANQAECggIDgAAAA==.',
Vs='Vsaguzz:BAAANQADCggIGgABNQAECgoKQwAZAMQSAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQICQAAAA==.',
Wa='Waroo:BAAANQADCggICAAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Wickïdus:BAAANQABCggIEAAAAA==.Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECggIEAAAAA==.',
Xa='Xaphelion:BAAANQAECgEIAQAAAA==.Xazio:BAABNQAECn8/AAIdAAoKoxlVEAAlAgAdAAoKoxlVEAAlAgAAAA==.',
Yi='Yiang:BAABNQAECn8WAAIaAAcKChujJQD2AQAaAAcKChujJQD2AQAAAA==.Yiav:BAAANQAECgIIAgABNQAFFAQICwACADIVAA==.',
Yl='Ylndrysa:BAABNQAECn9lAAMYAAoK+xqqGAB5AgAYAAoK+xqqGAB5AgAFAAQKXAqiVQDIAAAAAA==.',
Ze='Zedrock:BAACNQAFFH8IAAIUAAQKMw8nBADXAAAUAAQKMw8nBADXAAA1AAQKf0kAAxQACgo2JD0BAEADABQACgo2JD0BAEADAAQAAgpbC4paATcAAAAA.Zeezu:BAAANQAECgMIAwAAAA==.Zekodian:BAAANQADCgQIBAAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAABNQAECn8YAAMTAAkK1Qc1qQAaAQATAAkK1Qc1qQAaAQAOAAgK+wLSTAB3AAAAAA==.Zhitolight:BAAANQAECggIDAABNQAFFAYICQATAG8WAA==.',
Zu='Zuro:BAABNQAECn8eAAIGAAkKoAcTwACDAQAGAAkKoAcTwACDAQAAAA==.',
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
