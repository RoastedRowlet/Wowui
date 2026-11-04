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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Evoker-Devastation','Mage-Arcane','Druid-Balance','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Priest-Shadow','Shaman-Elemental','Shaman-Enhancement','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Druid-Restoration','Warrior-Arms','Monk-Windwalker','DemonHunter-Havoc','Rogue-Subtlety','Mage-Fire','DemonHunter-Devourer','Paladin-Protection','Druid-Feral','Druid-Guardian','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','DemonHunter-Vengeance','Monk-Mistweaver',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Ablestract:BAAANQADCgUIBQAAAA==.',
Ac='Acid:BAAANQAECgIIBAAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgYIDAAAAA==.',
Ak='Akamma:BAAANQAECgQICAAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliwings:BAAANQAECgYIEwAAAA==.',
Am='Amarokk:BAAANQAECgUICwAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
An='Ancestor:BAAANQADCggIFQAAAA==.Antumblare:BAAANQAECggICwABNQAECgIIAgABAAAAAA==.',
Ar='Arioch:BAAANQAECgYICQAAAA==.',
As='Ashireg:BAAANQAFFAMIBAAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgkJKwACACsXAA==.',
Au='Auriyan:BAAANQADCgYIBgAAAA==.',
Az='Azimondius:BAABNQAECn8sAAIDAAoKeBcJDQCSAgADAAoKeBcJDQCSAgAAAA==.Azmora:BAAANQAECgUICAAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQADCgYIBgABNQAECgoKHAAEAEgIAA==.Belthora:BAAANQAECgQICQAAAA==.Benry:BAABNQAECn8aAAIFAAgKMRy+JgCeAgAFAAgKMRy+JgCeAgAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAAAAA==.Bistroboy:BAAANQAECggIAQAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgcIFwAAAA==.',
Br='Brianjany:BAAANQAECgQIBwAAAA==.Brook:BAAANQABCgEIAQAAAA==.Browntotem:BAAANQAECgEIAQAAAA==.',
Bu='Bubblehëarth:BAAANQAECgMIBgAAAA==.Bulgestomper:BAABNQAECn8iAAQGAAoKIhzfJQB9AgAGAAoKIhzfJQB9AgAHAAEKFAPCFAAoAAAIAAEKUwMDnQAiAAAAAA==.Bully:BAAANQAECgYICwAAAA==.Burbuja:BAAANQAECgUIDgAAAA==.Buschgore:BAAANQAECgEIAQAAAA==.',
['Bá']='Bádoink:BAAANQADCgcIBwAAAA==.',
Ca='Calimari:BAAANQADCggICAAAAA==.Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.Caste:BAAANQADCgcIDQABNQAECggILwAJAJUXAA==.Castr:BAAANQAECgQIBAABNQAECgIIBAABAAAAAA==.',
Ce='Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Chargeantrot:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.Cherrypalaid:BAABNQAECn8bAAMKAAkKcxYsQgBcAgAKAAkKcxYsQgBcAgALAAEKdAFp1gEaAAAAAA==.Chicntrl:BAABNQAECn8ZAAIMAAcKqBoIDgAWAgAMAAcKqBoIDgAWAgABNQAECgkJHwANAK4bAA==.',
Co='Cobble:BAABNQAECn8lAAMOAAoKzA3yPQChAQAOAAoKzA3yPQChAQAPAAIKBAnYKQBtAAAAAA==.Colhap:BAABNQAECn8yAAINAAoK1yAmCwAxAwANAAoK1yAmCwAxAwAAAA==.Conjure:BAABNQAECn8iAAQQAAoKFRJZDQAaAQARAAcKvBFjXgCAAQAQAAcK8A9ZDQAaAQASAAMKLBLHGQB1AAAAAA==.Corbina:BAAANQAECggIAgAAAA==.Corehammer:BAAANQADCgYIDQAAAA==.',
Cr='Creamsocket:BAAANQAECgQJBgAAAA==.Cru:BAAANQAECgcIDAAAAA==.Crui:BAAANQADCggICAAAAA==.',
Cu='Culligan:BAABNQAECn9eAAMEAAoKYRq1MgBXAgAEAAoKYRq1MgBXAgATAAIKyg0zJgB4AAAAAA==.Cuttingcrew:BAAANQADCggICAAAAA==.',
Cy='Cygwin:BAABNQAECn8VAAMCAAgKcBfJXgDyAQACAAgKcBfJXgDyAQAOAAEKAADaOAExAAAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAABNQAECn8aAAMUAAkKgQr0ZgB1AQAUAAgKyQr0ZgB1AQAVAAIKhwcYnABaAAAAAA==.Datmage:BAAANQAECgEIAQAAAA==.',
De='Decomposed:BAAANQADCgMIAwAAAA==.Deigo:BAAANQADCggICAABNQAECgoKPAAOAPYcAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECggIDwAAAA==.Demunzz:BAAANQADCggIFgAAAA==.Destruction:BAABNQAECn8hAAIWAAgK4wVpbwA3AQAWAAgK4wVpbwA3AQAAAA==.Deylei:BAAANQAECgEIAQAAAA==.',
Di='Dithur:BAAANQADCgMIAwAAAA==.Divinespark:BAABNQAECn8hAAIXAAgK0xq+RwBPAgAXAAgK0xq+RwBPAgAAAA==.',
Do='Doinkbigs:BAABNQAECn8nAAIRAAgKLQw8mQCnAQARAAgKLQw8mQCnAQAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Dooko:BAAANQAECgEIAQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAAANQAECgYIDwABNQAECgcIDwABAAAAAA==.',
Dr='Draethno:BAAANQADCgUIBwAAAA==.Drambush:BAAANQADCgMIAwAAAA==.Draqulen:BAAANQABCgYICQAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Drewsilla:BAAANQADCgIIAgAAAA==.Druidrose:BAABNQAECn8VAAMYAAcKNwZfPgDTAAAYAAcKNwZfPgDTAAAFAAEKMQI6xwAbAAAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAABNQAECn8UAAIRAAkKOBjRYQAzAgARAAkKOBjRYQAzAgAAAA==.Dustbroom:BAAANQADCgQIBAAAAA==.',
['Dà']='Dàvë:BAAANQAECgQIBAABNQAECggILwAJAJUXAA==.',
Ea='Eap:BAAANQADCggIEQAAAA==.Eazye:BAACNQAFFH8GAAINAAIKSRqZCwCtAAANAAIKSRqZCwCtAAA1AAQKf0QAAg0ACgrfIPsNAA4DAA0ACgrfIPsNAA4DAAAA.',
Ec='Ectojudge:BAAANQADCgUIBQAAAA==.',
Ed='Edgeffs:BAABNQAECn8hAAIZAAgK5Qf6vQCCAQAZAAgK5Qf6vQCCAQAAAA==.',
El='Elentiya:BAABNQAECn8gAAIXAAoKpRk4MACnAgAXAAoKpRk4MACnAgAAAA==.Elphs:BAABNQAECn8WAAIaAAoKdBciIAAtAgAaAAoKdBciIAAtAgAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQAECgQIAwAAAA==.',
Fa='Faarâm:BAAANQAECgMIAgAAAA==.',
Fe='Felorc:BAABNQAECn8YAAIRAAYKzxA7vgBQAQARAAYKzxA7vgBQAQAAAA==.Fenton:BAABNQAECn8nAAIXAAoKmiK9EgAXAwAXAAoKmiK9EgAXAwAAAA==.Fentun:BAABNQAECn8cAAIKAAkKoiajCACDAwAKAAkKoiajCACDAwAAAA==.',
Fo='Foulplay:BAAANQAECgUIBQAAAA==.',
Fr='Free:BAAANQAECgEIAQAAAA==.',
Ga='Gabacadabra:BAAANQABCgIIAgAAAA==.Gali:BAAANQABCggIGQAAAA==.',
Ge='Gelektrael:BAABNQAECn8iAAMSAAgKOhJ7DQAhAgASAAgKOhJ7DQAhAgARAAQKOAdMDgGvAAAAAA==.Getchya:BAAANQAECgYICwABNQAECggILwAJAJUXAA==.',
Gh='Ghoostt:BAABNQAECn8iAAIbAAkK3BXVHwDRAQAbAAkK3BXVHwDRAQABNQAFFAUIEAALAOUVAA==.Ghostzz:BAACNQAFFH8QAAILAAUK5RWEDwDjAAALAAUK5RWEDwDjAAA1AAQKf0kAAgsACgreI4QVAPcCAAsACgreI4QVAPcCAAAA.',
Gl='Gloríous:BAAANQAECgYIBwABNQAECgoKIQAYAMkTAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Go='Goriath:BAAANQAECgUICQAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQAECgYIDgAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAFFAEIAQAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAAANQAECgcIEgAAAA==.Haldire:BAAANQABCgQIBAAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haruto:BAAANQADCggICAAAAA==.Haschel:BAAANQADCgcICgAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAABNQAECn8rAAIKAAcK1QtnaABLAQAKAAcK1QtnaABLAQAAAA==.Hoshi:BAAANQADCgQIBAABNQAECgkJLgANAGIlAA==.',
Hu='Hurtak:BAAANQAECgYIDAAAAA==.',
Hy='Hycisan:BAABNQAECn8qAAIKAAkKLh2eEwDwAgAKAAkKLh2eEwDwAgAAAA==.Hysteria:BAAANQAECgUIEQAAAA==.',
Ic='Icon:BAAANQADCgcICwAAAA==.Icydoodad:BAAANQAECggIDwABNQAECggILwAJAJUXAA==.',
Ik='Ikdutak:BAABNQAECn8cAAIEAAoKSAisbwChAQAEAAoKSAisbwChAQAAAA==.',
Il='Illusionwr:BAABNQAECn8XAAIZAAgKRBB5fABZAQAZAAgKRBB5fABZAQABNQAECgoKPwAbAHQgAA==.',
Ja='Jagerspell:BAABNQAECn9LAAMcAAoKYSRsCQAXAwAcAAoKnSNsCQAXAwAJAAQKfCS9TACOAQAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAABNQAECn8WAAIdAAkKzCXfAAAYAwAdAAkKzCXfAAAYAwAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAABNQAECn8fAAMPAAcKAQltIABYAQAPAAcKAQltIABYAQACAAMKpQE/BgFcAAAAAA==.Kanastra:BAABNQAECn8rAAIeAAkKfxa4GAC4AQAeAAkKfxa4GAC4AQABNQAECgoKLAADAHgXAA==.Karraa:BAAANQADCgYJBgABNQAECgcIHwAPAAEJAA==.Kaylib:BAABNQAECn8oAAIdAAgKDA87AwDTAQAdAAgKDA87AwDTAQAAAA==.',
Ke='Kesi:BAAANQAECgMIAwAAAA==.',
Kh='Khaztharion:BAABNQAECn8aAAIDAAkK6xKYCQCoAQADAAkK6xKYCQCoAQABNQAECgoKJwARAJsfAA==.Khendrick:BAABNQAECn87AAMLAAoKDRfnWADtAQALAAkKPhPnWADtAQAfAAgKjBVIJAC+AQAAAA==.',
Ki='Kinarra:BAAANQABCgYIBgAAAA==.Kittykatt:BAABNQAECn85AAIFAAoKnB0OEACFAgAFAAoKnB0OEACFAgAAAA==.',
Kn='Knowledge:BAABNQAECn8eAAIEAAgKviBDSgDtAgAEAAgKviBDSgDtAgAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECggIKQAZAPAXAA==.',
Kr='Kraggo:BAABNQAECn9DAAMRAAoK0B5sGQAhAwARAAoK0B5sGQAhAwASAAIKPA9dWQB0AAAAAA==.Krimzin:BAAANQAFFAEIAQABNQAFFAcIDgAGABUYAA==.',
['Kí']='Kíllerwolf:BAAANQAECgUIDAAAAA==.',
La='Larsen:BAABNQAECn8jAAIOAAgK4xpCPQCBAgAOAAgK4xpCPQCBAgAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQAECgYICgAAAA==.',
Le='Leap:BAABNQAECn8xAAMgAAoKdRTfDQCdAQAgAAkKyhPfDQCdAQAhAAgK0RD4KgD7AAAAAA==.Legbah:BAAANQADCggIGAABNQAECggILwAJAJUXAA==.',
Li='Lightmare:BAAANQADCgYIBgAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lonesdove:BAAANQABCgIIAgAAAA==.Lookadragon:BAAANQAECgUIDQAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Lunacy:BAAANQAECgUIEQAAAA==.',
Ly='Lynngosa:BAABNQAECn9BAAMiAAoKrhH3HAD8AQAiAAoKrhH3HAD8AQAjAAcKJA2TDgBdAQAAAA==.',
Ma='Magebob:BAABNQAECn8bAAMEAAkKdQlPiwBiAQAEAAkKRglPiwBiAQATAAIK6Ai0OAAtAAAAAA==.Magisterium:BAABNQAECn8cAAIXAAkKXgiTXQCOAQAXAAkKXgiTXQCOAQAAAA==.Mario:BAAANQAECgEIAQAAAA==.Marlfox:BAAANQADCgEIAQAAAA==.Maulware:BAAANQADCgQICwAAAA==.',
Me='Meingaree:BAAANQABCgcICgAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.Metronome:BAAANQADCgEIAQAAAA==.',
Mi='Mightyguzz:BAABNQAECn87AAIZAAoKxBLqVgDDAQAZAAoKxBLqVgDDAQAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAABNQAECn8UAAIhAAgKOBtBEABcAgAhAAgKOBtBEABcAgAAAA==.Minimuffn:BAABNQAECn8dAAMUAAgKiBm9QwAMAgAUAAcKgBy9QwAMAgAWAAIKtAvutwBYAAAAAA==.Misericordia:BAABNQAECn8qAAINAAcKiA7PJgARAQANAAcKiA7PJgARAQAAAA==.',
['Mø']='Møønchild:BAAANQAECgQICgAAAA==.',
Na='Nafega:BAAANQADCgUICQAAAA==.Nanaish:BAAANQAECgUICAAAAA==.Naredionis:BAAANQADCgMIAwAAAA==.Natë:BAABNQAECn9AAAIkAAoKwBeOCwDNAQAkAAoKwBeOCwDNAQAAAA==.',
Ne='Nebakenazzer:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.Necrotalon:BAAANQAECgYIBwAAAA==.Nemesia:BAABNQAECn8pAAMZAAgK8BegXgCqAQAZAAgK8BegXgCqAQAlAAUKKBC1GAAVAQAAAA==.Neonsunrise:BAACNQAFFH8GAAINAAIKSxoLDACmAAANAAIKSxoLDACmAAA1AAQKf0MAAg0ACgqDIjgHAGcDAA0ACgqDIjgHAGcDAAAA.',
Nh='Nharuna:BAABNQAECn8sAAIGAAoKsg9agAAMAgAGAAoKsg9agAAMAgAAAA==.',
Ni='Nieloriel:BAABNQAECn8iAAIKAAkK7Q9rQQDbAQAKAAkK7Q9rQQDbAQAAAA==.Nimbus:BAABNQAECn8aAAMIAAoKjBT2IAApAQAGAAkKQhRbfwBzAQAIAAcKgQ/2IAApAQABNQAFFAcIGwAOADwXAA==.Niykee:BAABNQAECn8lAAQJAAoKYyHSFgDGAgAJAAkK/B3SFgDGAgAmAAUKrBgZDgBcAQAcAAMKiSF4ggDGAAAAAA==.',
No='Noboundss:BAABNQAECn8tAAMbAAoKmhxGHQCvAgAbAAoKGhxGHQCvAgAeAAUKLxfXPwBNAQAAAA==.Noztra:BAABNQAECn89AAMTAAoKfgxkIADmAAAEAAoKcAlaywDvAQATAAUKLBFkIADmAAAAAA==.',
Ns='Nsolant:BAAANQAECgYIDgAAAA==.',
Nu='Nubsy:BAAANQAECgEIAQAAAA==.Nuker:BAABNQAECn8ZAAIEAAYK1AuJzADlAAAEAAYK1AuJzADlAAAAAA==.Nukron:BAAANQAECgYIBgAAAA==.',
Oh='Ohgr:BAABNQAECn8aAAMlAAcKCwjwHADeAAAZAAcKzwdFzQBaAQAlAAYKMQjwHADeAAAAAA==.Ohshifty:BAABNQAECn9UAAMFAAoKixrnEwBSAgAFAAoKixrnEwBSAgAYAAIK5gGIdQA1AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgYIDwAAAA==.',
Or='Orbsicles:BAABNQAECn8iAAMeAAkKHxo0IgA5AgAeAAkKHxo0IgA5AgAnAAIKlBc5JgCIAAAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQAECgMIBAAAAA==.Papitomyrey:BAAANQAECgcIDAABNQAECgoKJAAfAL8hAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAACNQAFFH8KAAIUAAQKihroDAA+AQAUAAQKihroDAA+AQA1AAQKfz8AAxQACgp+JR4EALIDABQACgp+JR4EALIDABYAAgoAAJKwAAAAAAAA.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQABCgQIBQAAAA==.Pooter:BAABNQAECn8VAAIGAAgKUwUmCgHyAAAGAAgKUwUmCgHyAAAAAA==.Powpow:BAABNQAECn81AAIcAAoKwxmPHwBhAgAcAAoKwxmPHwBhAgAAAA==.',
Pr='Prejudice:BAABNQAECn8iAAIKAAgK4g4ydQC4AQAKAAgK4g4ydQC4AQAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAACNQAFFH8HAAIYAAMKsgl6CwC+AAAYAAMKsgl6CwC+AAA1AAQKfzwAAxgACgprD4khAJwBABgACgprD4khAJwBACAABwo8DcMYAHABAAAA.',
['Pû']='Pûff:BAABNQAECn8pAAIiAAkKGx7pDwCrAgAiAAkKGx7pDwCrAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQAECgMIAwAAAA==.Rainhoof:BAABNQAECn8iAAMgAAgKxBR3FgCTAQAgAAYKXBN3FgCTAQAYAAUK5An/SQDoAAAAAA==.Ralneth:BAACNQAFFH8jAAIiAAgKSRJjBAAzAgAiAAgKSRJjBAAzAgA1AAQKfzUAAiIACgpRGMoWAEsCACIACgpRGMoWAEsCAAAA.Randomtask:BAAANQADCggIEAAAAA==.Rapala:BAABNQAECn8dAAIRAAcKbhx6awAbAgARAAcKbhx6awAbAgAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECgcIHQARAG4cAA==.Raspútin:BAAANQAECgMIAwABNQAECggIDgABAAAAAA==.Ravos:BAAANQABCgIIAgAAAA==.Rawdoinkers:BAAANQAECgQIBgAAAA==.Rawkfice:BAAANQADCggIJwAAAA==.',
Re='Redlefbarg:BAAANQADCgQIBwAAAA==.Renakir:BAAANQADCgEIAQAAAA==.Renly:BAABNQAECn8hAAIfAAgKCRzCFQBRAgAfAAgKCRzCFQBRAgAAAA==.Restoral:BAAANQAECgIIAQAAAA==.',
Ri='Riordan:BAABNQAECn8iAAMGAAkKAiUlMADcAgAGAAkKAiUlMADcAgAIAAEKnx2MegBXAAAAAA==.Rivvetear:BAAANQADCgIIAgAAAA==.',
Rj='Rjolz:BAACNQAFFH8SAAQUAAYK2CA6CwBaAQAUAAUK2CA6CwBaAQAWAAMKAxWDFgCMAAAVAAIKxBNwHQBJAAA1AAQKf2cABBQACgp3JuYCAMgDABQACgp3JuYCAMgDABYACgo9H1kKANMCABUACQqDHzcWAGsCAAAA.',
Ro='Roflchopr:BAABNQAECn85AAILAAoK2xNSkQACAgALAAoK2xNSkQACAgAAAA==.Roflkin:BAAANQAECgUICgAAAA==.',
Sa='Sadcow:BAABNQAECn88AAIOAAoK9hymGQB4AgAOAAoK9hymGQB4AgAAAA==.Sandalfon:BAAANQADCgYICQAAAA==.Sanleron:BAABNQAECn8hAAMfAAkKjhtVCgBjAgAfAAkK2xlVCgBjAgALAAgK7RXYoADgAQAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIAwAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQAECgEIAQAAAA==.',
Sh='Sharayse:BAAANQAECgcIBwAAAA==.Sharmee:BAAANQAECggIEwAAAA==.Shiftycapone:BAABNQAECn8fAAIFAAoKshQjGgAFAgAFAAoKshQjGgAFAgAAAA==.Shmelverino:BAAANQAECgQICwAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shockulater:BAAANQADCgEIAQAAAA==.Shogu:BAABNQAECn8mAAMZAAgKegzsqgCyAQAZAAgKVArsqgCyAQAkAAEKDhNRQAA+AAAAAA==.Sháde:BAABNQAECn8VAAMQAAcKIw3LCwCqAQAQAAcKIw3LCwCqAQASAAEKGgu+eAA1AAAAAA==.',
Si='Simpmother:BAEBNQAECn8qAAIRAAoK8A86hADbAQARAAoK8A86hADbAQAAAA==.',
Sk='Skadie:BAAANQADCgYIBgABNQAECgoKQQAiAK4RAA==.',
Sl='Sladepriest:BAAANQAECgMIAwAAAA==.Slingablade:BAABNQAECn86AAMeAAoK9hrGFgCqAgAeAAoK9hrGFgCqAgAnAAMKdQg4JABLAAAAAA==.',
Sm='Smallfoot:BAAANQADCgEIAQAAAA==.',
Sn='Sniffsniff:BAABNQAECn8WAAIKAAgKYCM8EgD+AgAKAAgKYCM8EgD+AgABNQAFFAcIFgACABYlAA==.',
So='Solvi:BAAANQAECgUICgAAAA==.Sonira:BAAANQADCgEIAQAAAA==.Sorá:BAABNQAECn81AAIZAAoK2yIfDwAPAwAZAAoK2yIfDwAPAwABNQAECgoKOQAWAPAXAA==.Soulbrand:BAAANQAECgMIBQAAAA==.',
Sp='Spellz:BAAANQADCgcIDAABNQAECgQIBgABAAAAAA==.',
St='Stabathuh:BAABNQAECn8vAAMJAAgKlRdxEgCHAQAcAAgK2BGNOQDTAQAJAAgKqhRxEgCHAQAAAA==.Stabnskullz:BAAANQAECgQJBAABNQAECggIDwABAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIIAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECggILwAJAJUXAA==.Stoopidlock:BAAANQADCggIGwABNQAECggILwAJAJUXAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECggILwAJAJUXAA==.Stoopidrood:BAAANQAECgQIBQABNQAECggILwAJAJUXAA==.Stoopidtroll:BAAANQADCgEIAQABNQAECggILwAJAJUXAA==.Stoopidwarur:BAABNQAECn8VAAIlAAgKsBw1BQBWAgAlAAgKsBw1BQBWAgABNQAECggILwAJAJUXAA==.Stormclaw:BAABNQAECn8gAAInAAgKugmyFwA0AQAnAAgKugmyFwA0AQAAAA==.Styne:BAAANQAECgMIAwABNQAECgoKPAAOAPYcAA==.',
Su='Sufiya:BAABNQAECn8aAAIGAAkKxQanrACrAQAGAAkKxQanrACrAQAAAA==.Suki:BAABNQAECn89AAIoAAoKryA6BgA3AwAoAAoKryA6BgA3AwAAAA==.Sulfion:BAAANQAECgQIBgAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYIEAAAAA==.',
Sy='Sylveria:BAAANQAECgIIAwAAAA==.Sylvershadow:BAABNQAECn8aAAIGAAYKOwnswADsAAAGAAYKOwnswADsAAAAAA==.Syphon:BAABNQAECn9RAAMnAAoKiSRXAQAiAwAnAAoKiSRXAQAiAwAbAAQK+Aa9bgBBAAAAAA==.',
['Sý']='Sýrin:BAAANQADCggJCgAAAA==.',
Ta='Tandarilada:BAAANQAECgEIAQAAAA==.Tanfer:BAAANQAECgEIAQAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECn8qAAIZAAoKGBtSbQBKAgAZAAoKGBtSbQBKAgAAAA==.Thndrstrmlol:BAAANQAECgMIAgAAAA==.',
Ti='Titanic:BAAANQAECgUIBgAAAA==.',
To='Tomcruise:BAABNQAECn8mAAILAAkKOh2lWwCFAgALAAkKOh2lWwCFAgAAAA==.Totemlyawsum:BAAANQAECgYICwAAAA==.',
Tr='True:BAAANQAECgQIBgAAAA==.',
Tw='Twotone:BAAANQADCgcICAAAAA==.',
Ul='Ulkthar:BAAANQAECgUIBQABNQAFFAUICwAEAFUKAA==.',
Un='Unholyhammer:BAAANQABCgMIAQABNQAECggIDwABAAAAAA==.',
Va='Vacunamatata:BAAANQAECgUIDQAAAA==.Vaiyrnlol:BAACNQAFFH8LAAICAAQKMhXTDgApAQACAAQKMhXTDgApAQA1AAQKfzIAAwIACgqRHWIhAOMCAAIACgqRHWIhAOMCAA4ACApYHz8pAAYCAAAA.Vanlin:BAABNQAECn8dAAIYAAgKHBt0GwBcAgAYAAgKHBt0GwBcAgAAAA==.',
Ve='Vexxdr:BAABNQAECn8/AAMYAAoKbBX8HADNAQAYAAoKbBX8HADNAQAFAAkK1RY7JwCMAQABNQAECgoKRgACALcjAA==.Vexxs:BAABNQAECn9GAAMCAAoKtyNQCQBmAwACAAoKtyNQCQBmAwAOAAcKbBcLTQBpAQAAAA==.',
Vo='Voidsuzu:BAABNQAECn88AAIeAAoKhhVIHQBqAgAeAAoKhhVIHQBqAgAAAA==.Vormedicus:BAAANQAECggIDgAAAA==.',
Vs='Vsaguzz:BAAANQADCggIFwABNQAECgoKOwAZAMQSAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQICQAAAA==.',
Wa='Waroo:BAAANQADCggICAAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Wickïdus:BAAANQABCggIEAAAAA==.Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECgUIDgAAAA==.',
Xa='Xaphelion:BAAANQAECgEIAQAAAA==.Xazio:BAABNQAECn87AAIfAAoKoxlTDAA2AgAfAAoKoxlTDAA2AgAAAA==.',
Yi='Yiang:BAABNQAECn8WAAIaAAcKChujJQD2AQAaAAcKChujJQD2AQAAAA==.',
Yl='Ylndrysa:BAABNQAECn9cAAMYAAoKdhiqGAB5AgAYAAoKdhiqGAB5AgAFAAQKXAozSgDIAAAAAA==.',
Ze='Zedrock:BAABNQAECn84AAMTAAoKPiL+AQDsAgATAAoKPiL+AQDsAgAEAAIKWwvVPAE+AAAAAA==.Zeezu:BAAANQAECgMIAwAAAA==.Zekodian:BAAANQADCgQIBAAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAAANQAECggIEwAAAA==.Zhitolight:BAAANQAECgQICgABNQAFFAYICAAXAJcSAA==.',
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
