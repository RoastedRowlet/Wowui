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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Evoker-Devastation','Mage-Arcane','Druid-Balance','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Shaman-Elemental','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Warlock-Demonology','Warrior-Arms','Monk-Windwalker','DemonHunter-Havoc','Rogue-Subtlety','Mage-Fire','Shaman-Enhancement','DemonHunter-Devourer','Paladin-Protection','Druid-Feral','Druid-Guardian','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','Druid-Restoration','DemonHunter-Vengeance','Monk-Mistweaver',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Ablestract:BAAANQADCgUIBQAAAA==.',
Ac='Acid:BAAANQAECgIIBAAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgUICwAAAA==.',
Ak='Akamma:BAAANQAECgUICAAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliwings:BAAANQAECgYIEwAAAA==.',
Am='Amarokk:BAAANQAECgUICwAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
An='Ancestor:BAAANQADCggIFQAAAA==.Antumblare:BAAANQAECggICwABNQAECgIIAgABAAAAAA==.',
Ar='Arioch:BAAANQAECgYICQAAAA==.',
As='Ashireg:BAAANQAFFAMIAwAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgkJJgACANkUAA==.',
Az='Azimondius:BAABNQAECn8pAAIDAAoKeBcJDQCSAgADAAoKeBcJDQCSAgAAAA==.Azmora:BAAANQAECgMIAwAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQADCgYIBgABNQAECgkJFgAEALgGAA==.Belthora:BAAANQAECgQICQAAAA==.Benry:BAABNQAECn8aAAIFAAgKMRy+JgCeAgAFAAgKMRy+JgCeAgAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAAAAA==.Bistroboy:BAAANQAECggIAQAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgcIFwAAAA==.',
Br='Brianjany:BAAANQAECgQIBwAAAA==.Browntotem:BAAANQAECgEIAQAAAA==.',
Bu='Bubblehëarth:BAAANQAECgMIBgAAAA==.Bulgestomper:BAABNQAECn8iAAQGAAoKIhymFQCmAgAGAAoKIhymFQCmAgAHAAEKFAPCFAAoAAAIAAEKUwMDnQAiAAAAAA==.Bully:BAAANQAECgYICwAAAA==.Burbuja:BAAANQAECgQIDQAAAA==.Buschgore:BAAANQADCggIFAAAAA==.',
['Bá']='Bádoink:BAAANQADCgcIBwAAAA==.',
Ca='Calimari:BAAANQADCggICAAAAA==.Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.Caste:BAAANQADCgcIDQABNQAECggIKQAJAJUXAA==.Castr:BAAANQAECgQIBAABNQAECgIIBAABAAAAAA==.',
Ce='Celessaria:BAAANQADCgYIEgAAAA==.Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Chargeantrot:BAAANQAECgEIAQABNQAECggIDwABAAAAAA==.Cherrypalaid:BAABNQAECn8bAAMKAAkKcxYsQgBcAgAKAAkKcxYsQgBcAgALAAEKdAFp1gEaAAAAAA==.Chicntrl:BAABNQAECn8ZAAIMAAcKqBoIDgAWAgAMAAcKqBoIDgAWAgABNQAFFAIIAgABAAAAAA==.',
Co='Cobble:BAABNQAECn8eAAINAAoK/wySNACEAQANAAoK/wySNACEAQAAAA==.Colhap:BAABNQAECn8xAAIOAAoK5SAmCwAxAwAOAAoK5SAmCwAxAwAAAA==.Conjure:BAABNQAECn8ZAAMPAAkKlBB9BwA7AQAPAAcK8A99BwA7AQAQAAMKLBIiFAB3AAAAAA==.Corehammer:BAAANQADCgYIDQAAAA==.',
Cr='Creamsocket:BAAANQAECgQJBgAAAA==.Cru:BAAANQAECgcICwAAAA==.',
Cu='Culligan:BAABNQAECn9TAAMEAAoKnxkFJQBiAgAEAAoKnxkFJQBiAgARAAIKyg0YHgB9AAAAAA==.Cuttingcrew:BAAANQADCggICAAAAA==.',
Cy='Cygwin:BAABNQAECn8UAAMCAAcKjhnJXgDyAQACAAcKjhnJXgDyAQANAAEKAADaOAExAAAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAABNQAECn8aAAMSAAkKgQr0ZgB1AQASAAgKyQr0ZgB1AQATAAIKhwcYnABaAAAAAA==.Datmage:BAAANQAECgEIAQAAAA==.',
De='Decomposed:BAAANQADCgMIAwAAAA==.Deigo:BAAANQADCggICAABNQAECgoKOAANAJMcAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECggIDwAAAA==.Demunzz:BAAANQADCggIFgAAAA==.Destruction:BAABNQAECn8fAAIUAAgK4wVpbwA3AQAUAAgK4wVpbwA3AQAAAA==.Deylei:BAAANQAECgEIAQAAAA==.',
Di='Dithur:BAAANQADCgMIAwAAAA==.Divinespark:BAABNQAECn8fAAIVAAgK0xq+RwBPAgAVAAgK0xq+RwBPAgAAAA==.',
Do='Doinkbigs:BAABNQAECn8iAAIWAAgK9wuLawAnAQAWAAgK9wuLawAnAQAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Dooko:BAAANQAECgEIAQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAAANQAECgcIDAABNQAECggIDwABAAAAAA==.',
Dr='Draethno:BAAANQADCgUIBwAAAA==.Drambush:BAAANQADCgMIAwAAAA==.Draqulen:BAAANQABCgYICQAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Drewsilla:BAAANQADCgIIAgAAAA==.Druidrose:BAAANQAECgYIEwAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAAANQAECggIDgAAAA==.Dustbroom:BAAANQADCgQIBAAAAA==.',
['Dà']='Dàvë:BAAANQAECgQIBAABNQAECggIKQAJAJUXAA==.',
Ea='Eap:BAAANQADCggIEQAAAA==.Eazye:BAABNQAECn8+AAIOAAoKZx77DQAOAwAOAAoKZx77DQAOAwAAAA==.',
Ec='Ectojudge:BAAANQADCgUIBQAAAA==.',
Ed='Edgeffs:BAABNQAECn8fAAIXAAgK5Qf6vQCCAQAXAAgK5Qf6vQCCAQAAAA==.',
El='Elentiya:BAABNQAECn8gAAIVAAoKpRk4MACnAgAVAAoKpRk4MACnAgAAAA==.Elphs:BAABNQAECn8WAAIYAAoKdBciIAAtAgAYAAoKdBciIAAtAgAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQAECgQIAwAAAA==.',
Fa='Faarâm:BAAANQAECgMIAgAAAA==.',
Fe='Felorc:BAABNQAECn8YAAIWAAYKzxA7vgBQAQAWAAYKzxA7vgBQAQAAAA==.Fenton:BAABNQAECn8kAAIVAAoKRSGyHwDxAgAVAAoKRSGyHwDxAgAAAA==.Fentun:BAABNQAECn8cAAIKAAkKoiajCACDAwAKAAkKoiajCACDAwAAAA==.',
Fo='Foulplay:BAAANQAECgUIBQAAAA==.',
Fr='Free:BAAANQAECgEIAQAAAA==.',
Ga='Gabacadabra:BAAANQABCgIIAgAAAA==.Gali:BAAANQABCggIFwAAAA==.',
Ge='Gelektrael:BAABNQAECn8gAAMQAAgKyhF7DQAhAgAQAAgKyhF7DQAhAgAWAAQKOAdMDgGvAAAAAA==.Getchya:BAAANQAECgYICwABNQAECggIKQAJAJUXAA==.',
Gh='Ghoostt:BAABNQAECn8ZAAIZAAkKuAvyPADQAQAZAAkKuAvyPADQAQABNQAFFAUIEAALAOUVAA==.Ghostzz:BAACNQAFFH8QAAILAAUK5RX6CgDuAAALAAUK5RX6CgDuAAA1AAQKf0IAAgsACgreI0gLABsDAAsACgreI0gLABsDAAAA.',
Gl='Gloríous:BAAANQAECgEIAQABNQAECggIIgAKAGwSAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgAAAA==.',
Go='Goriath:BAAANQAECgUICQAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQAECgYIDQAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgYICwAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAAANQAECgcIEgAAAA==.Haldire:BAAANQABCgQIBAAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haruto:BAAANQADCggICAAAAA==.Haschel:BAAANQADCgcICgAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAABNQAECn8pAAIKAAcK1QtQTwBaAQAKAAcK1QtQTwBaAQAAAA==.Hoshi:BAAANQADCgQIBAABNQAECgkJLgAOAGIlAA==.',
Hu='Hurtak:BAAANQAECgYIDAAAAA==.',
Hy='Hycisan:BAABNQAECn8hAAIKAAgKix3dMwCVAgAKAAgKix3dMwCVAgAAAA==.Hysteria:BAAANQAECgQICAAAAA==.',
Ic='Icon:BAAANQADCgcICwAAAA==.Icydoodad:BAAANQAECgUIBQABNQAECggIKQAJAJUXAA==.',
Ik='Ikdutak:BAABNQAECn8WAAIEAAkKuAazewBLAQAEAAkKuAazewBLAQAAAA==.',
Il='Illusionwr:BAAANQAECgcIEQABNQAECgoKPwAZAH0gAA==.',
Ja='Jagerspell:BAABNQAECn9HAAMaAAoKYSSoCAD+AgAaAAoK8yKoCAD+AgAJAAQKfCS9TACOAQAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAABNQAECn8WAAIbAAkKzCV2AACcAgAbAAkKzCV2AACcAgAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAABNQAECn8eAAMcAAcKAQltIABYAQAcAAcKAQltIABYAQACAAMKpQE/BgFcAAAAAA==.Kanastra:BAABNQAECn8oAAIdAAkKDRSREwCzAQAdAAkKDRSREwCzAQABNQAECgoKKQADAHgXAA==.Karraa:BAAANQADCgYJBgABNQAECgcIHgAcAAEJAA==.Kaylib:BAABNQAECn8mAAIbAAgKDA87AwDTAQAbAAgKDA87AwDTAQAAAA==.',
Ke='Kesi:BAAANQAECgMIAwAAAA==.',
Kh='Khaztharion:BAAANQAECgYIEQABNQAECgoKHgAWAJAfAA==.Khendrick:BAABNQAECn80AAMLAAkKgBYPWwCmAQAeAAgKjBVIJAC+AQALAAgKxREPWwCmAQAAAA==.',
Ki='Kinarra:BAAANQABCgYIBgAAAA==.Kittykatt:BAABNQAECn8vAAIFAAoKUhuUIgC7AgAFAAoKUhuUIgC7AgAAAA==.',
Kn='Knowledge:BAABNQAECn8eAAIEAAgKviBDSgDtAgAEAAgKviBDSgDtAgAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECggIKQAXAPAXAA==.',
Kr='Kraggo:BAABNQAECn8+AAMWAAoK0B5sGQAhAwAWAAoK0B5sGQAhAwAQAAIKPA9dWQB0AAAAAA==.Krimzin:BAAANQAFFAEIAQABNQAFFAcIDgAGABUYAA==.',
['Kí']='Kíllerwolf:BAAANQAECgUIDAAAAA==.',
La='Larsen:BAABNQAECn8gAAINAAgKqBpCPQCBAgANAAgKqBpCPQCBAgAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQAECgYICQAAAA==.',
Le='Leap:BAABNQAECn8hAAMfAAkKJRNlCgCVAQAfAAkKmxJlCgCVAQAgAAQKww93PwC9AAAAAA==.Legbah:BAAANQADCggIGAABNQAECggIKQAJAJUXAA==.',
Li='Lightmare:BAAANQADCgYIBgAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lonesdove:BAAANQABCgIIAgAAAA==.Lookadragon:BAAANQAECgUIDQAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Lunacy:BAAANQAECgQICAAAAA==.',
Ly='Lynngosa:BAABNQAECn9BAAMhAAoKrhFoEABlAQAhAAoKrhFoEABlAQAiAAcKJA2TDgBdAQAAAA==.',
Ma='Magebob:BAABNQAECn8VAAMEAAcKCwtInAAMAQAEAAcKCwtInAAMAQARAAEKAAB9UQAkAAAAAA==.Magisterium:BAAANQAECgUIDAAAAA==.Marlfox:BAAANQADCgEIAQAAAA==.Maulware:BAAANQADCgQICwAAAA==.',
Me='Meingaree:BAAANQABCgcICgAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.Metronome:BAAANQADCgEIAQAAAA==.',
Mi='Mightyguzz:BAABNQAECn83AAIXAAoKHxKWRwCxAQAXAAoKHxKWRwCxAQAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAABNQAECn8UAAIgAAgKOBtBEABcAgAgAAgKOBtBEABcAgAAAA==.Minimuffn:BAABNQAECn8dAAMSAAgKiBm9QwAMAgASAAcKgBy9QwAMAgAUAAIKtAvutwBYAAAAAA==.Misericordia:BAABNQAECn8qAAIOAAcKiA5GHgAWAQAOAAcKiA5GHgAWAQAAAA==.',
['Mø']='Møønchild:BAAANQAECgUIBwAAAA==.',
Na='Nafega:BAAANQADCgEIAQAAAA==.Nanaish:BAAANQAECgQIBwAAAA==.Natë:BAABNQAECn9AAAIjAAoKwBfTBwDhAQAjAAoKwBfTBwDhAQAAAA==.',
Ne='Nebakenazzer:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.Necrotalon:BAAANQAECgYIBgAAAA==.Nemesia:BAABNQAECn8pAAMXAAgK8BdjSACuAQAXAAgK8BdjSACuAQAkAAUKKBC1GAAVAQAAAA==.Neonsunrise:BAABNQAECn8+AAIOAAoKTiE4BwBnAwAOAAoKTiE4BwBnAwAAAA==.',
Nh='Nharuna:BAABNQAECn8mAAIGAAkKHhBagAAMAgAGAAkKHhBagAAMAgAAAA==.',
Ni='Nieloriel:BAABNQAECn8gAAIKAAkK5Q9mNgDFAQAKAAkK5Q9mNgDFAQAAAA==.Nimbus:BAABNQAECn8aAAMIAAoKjBQaGgAzAQAGAAkKQhSpXgCCAQAIAAcKgQ8aGgAzAQABNQAFFAcIGwANADwXAA==.Niykee:BAABNQAECn8kAAQJAAoKYyHSFgDGAgAJAAkK/B3SFgDGAgAlAAUKrBgZDgBcAQAaAAMKiSHlZgDEAAAAAA==.',
No='Noboundss:BAABNQAECn8rAAMZAAoKiRxGHQCvAgAZAAoKCRxGHQCvAgAdAAUKLxfXPwBNAQAAAA==.Noztra:BAABNQAECn87AAMRAAoKfgxkIADmAAAEAAoKcAlaywDvAQARAAUKLBFkIADmAAAAAA==.',
Ns='Nsolant:BAAANQAECgYIDQAAAA==.',
Nu='Nubsy:BAAANQAECgEIAQAAAA==.Nuker:BAAANQAECgQIEQAAAA==.Nukron:BAAANQADCggIEAAAAA==.',
Oh='Ohgr:BAABNQAECn8WAAMkAAcKzwfwHADeAAAXAAcKzwdFzQBaAQAkAAUK4QXwHADeAAAAAA==.Ohshifty:BAABNQAECn9FAAMFAAoKnBjxEQAqAgAFAAoKnBjxEQAqAgAmAAIK5gGIdQA1AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgYIDwAAAA==.',
Or='Orbsicles:BAABNQAECn8hAAMdAAgKpxo0IgA5AgAdAAgKpxo0IgA5AgAnAAIKlBc5JgCIAAAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQAECgIIAwAAAA==.Papitomyrey:BAAANQAECgcIDAABNQAECgoKJAAeAL8hAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAACNQAFFH8KAAISAAQKihroDAA+AQASAAQKihroDAA+AQA1AAQKfzgAAhIACgp+JR4EALIDABIACgp+JR4EALIDAAAA.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQABCgQIBQAAAA==.Pooter:BAABNQAECn8VAAIGAAgKUwUmCgHyAAAGAAgKUwUmCgHyAAAAAA==.Powpow:BAABNQAECn8tAAIaAAoKARl6GQBSAgAaAAoKARl6GQBSAgAAAA==.',
Pr='Prejudice:BAABNQAECn8gAAIKAAgK4g4ydQC4AQAKAAgK4g4ydQC4AQAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAACNQAFFH8FAAImAAIK9gUIDQBsAAAmAAIK9gUIDQBsAAA1AAQKfzgAAyYACgprDyAYALEBACYACgprDyAYALEBAB8ABwo8DcMYAHABAAAA.',
['Pû']='Pûff:BAABNQAECn8pAAIhAAkKGx7pDwCrAgAhAAkKGx7pDwCrAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQAECgMIAwAAAA==.Rainhoof:BAABNQAECn8gAAMfAAgKTBR3FgCTAQAfAAYKqRJ3FgCTAQAmAAUK5An/SQDoAAAAAA==.Ralneth:BAACNQAFFH8iAAIhAAcKkRRjBAAzAgAhAAcKkRRjBAAzAgA1AAQKfzIAAiEACgoRGMoWAEsCACEACgoRGMoWAEsCAAAA.Randomtask:BAAANQADCggIEAAAAA==.Rapala:BAABNQAECn8dAAIWAAcKbhx6awAbAgAWAAcKbhx6awAbAgAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECgcIHQAWAG4cAA==.Raspútin:BAAANQAECgMIAwABNQAECggIDgABAAAAAA==.Ravos:BAAANQABCgIIAgAAAA==.Rawdoinkers:BAAANQAECgIIAgAAAA==.Rawkfice:BAAANQADCggIIAAAAA==.',
Re='Redlefbarg:BAAANQADCgQIBwAAAA==.Renakir:BAAANQADCgEIAQAAAA==.Renly:BAABNQAECn8hAAIeAAgKCRzCFQBRAgAeAAgKCRzCFQBRAgAAAA==.Restoral:BAAANQAECgIIAQAAAA==.',
Ri='Riordan:BAABNQAECn8gAAMGAAgKYCUlMADcAgAGAAgKYCUlMADcAgAIAAEKnx2MegBXAAAAAA==.Rivvetear:BAAANQADCgIIAgAAAA==.',
Rj='Rjolz:BAACNQAFFH8RAAQSAAYK2CA6CwBaAQASAAUK2CA6CwBaAQAUAAMKAxWbEQCVAAATAAIKxBNwHQBJAAA1AAQKf1QABBIACgrXJeYCAMgDABIACQomJuYCAMgDABQACgpvHcgIAMMCABMACQoXHz4QAGcCAAAA.',
Ro='Roflchopr:BAABNQAECn8zAAILAAoKoBOqbAB7AQALAAoKoBOqbAB7AQAAAA==.Roflkin:BAAANQAECgQICQAAAA==.',
Sa='Sadcow:BAABNQAECn84AAINAAoKkxzKEgB4AgANAAoKkxzKEgB4AgAAAA==.Sandalfon:BAAANQADCgYICQAAAA==.Sanleron:BAABNQAECn8YAAMeAAgK+BYvHgAJAQALAAgK7RXYoADgAQAeAAUKzQ0vHgAJAQAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIAwAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQAECgEIAQAAAA==.',
Sh='Sharayse:BAAANQADCgYIEwAAAA==.Sharmee:BAAANQAECggIEgAAAA==.Shiftycapone:BAABNQAECn8ZAAIFAAoKWBKGFwDgAQAFAAoKWBKGFwDgAQAAAA==.Shmelverino:BAAANQAECgQICwAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shockulater:BAAANQABCgIIAgAAAA==.Shogu:BAABNQAECn8kAAMXAAgKegzsqgCyAQAXAAgKVArsqgCyAQAjAAEKDhNRQAA+AAAAAA==.Sháde:BAABNQAECn8VAAMPAAcKIw3LCwCqAQAPAAcKIw3LCwCqAQAQAAEKGgu+eAA1AAAAAA==.',
Si='Simpmother:BAEBNQAECn8qAAIWAAoK8A86hADbAQAWAAoK8A86hADbAQAAAA==.',
Sk='Skadie:BAAANQADCgYIBgABNQAECgoKQQAhAK4RAA==.',
Sl='Sladepriest:BAAANQAECgMIAwAAAA==.Slingablade:BAABNQAECn80AAMdAAoK3xrGFgCqAgAdAAoK3xrGFgCqAgAnAAMKdQhmHgBLAAAAAA==.',
Sm='Smallfoot:BAAANQADCgEIAQAAAA==.',
Sn='Sniffsniff:BAAANQAFFAIIAgABNQAFFAYIFAACAOklAA==.',
So='Solvi:BAAANQAECgUICgAAAA==.Sorá:BAABNQAECn8rAAIXAAoKWCK5DwDnAgAXAAoKWCK5DwDnAgABNQAECgoKOQAUAPAXAA==.Soulbrand:BAAANQAECgMIBQAAAA==.',
Sp='Spellz:BAAANQADCgcIDAABNQAECgMIBAABAAAAAA==.',
St='Stabathuh:BAABNQAECn8pAAMJAAgKlRevDQClAQAJAAgKqhSvDQClAQAaAAgKbAyrKQB3AQAAAA==.Stabnskullz:BAAANQAECgQJBAABNQAECggIDwABAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIIAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECggIKQAJAJUXAA==.Stoopidlock:BAAANQADCggIGwABNQAECggIKQAJAJUXAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECggIKQAJAJUXAA==.Stoopidrood:BAAANQAECgQIBQABNQAECggIKQAJAJUXAA==.Stoopidtroll:BAAANQADCgEIAQABNQAECggIKQAJAJUXAA==.Stoopidwarur:BAAANQAECggIEAABNQAECggIKQAJAJUXAA==.Stormclaw:BAABNQAECn8eAAInAAgKkAiyFwA0AQAnAAgKkAiyFwA0AQAAAA==.Styne:BAAANQADCggICAABNQAECgoKOAANAJMcAA==.',
Su='Sufiya:BAABNQAECn8aAAIGAAkKxQanrACrAQAGAAkKxQanrACrAQAAAA==.Suki:BAABNQAECn8zAAIoAAoKdSA6BgA3AwAoAAoKdSA6BgA3AwAAAA==.Sulfion:BAAANQAECgMIBAAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYIEAAAAA==.',
Sy='Sylveria:BAAANQAECgIIAwAAAA==.Sylvershadow:BAAANQAECgUIDwAAAA==.Syphon:BAABNQAECn9KAAMnAAoKKSOoAQCKAwAnAAoKKSOoAQCKAwAZAAIKVQGApQAOAAAAAA==.',
['Sý']='Sýrin:BAAANQADCggJCgAAAA==.',
Ta='Tandarilada:BAAANQAECgEIAQAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECn8qAAIXAAoKGBtSbQBKAgAXAAoKGBtSbQBKAgAAAA==.',
Ti='Titanic:BAAANQAECgUIBgAAAA==.',
To='Tomcruise:BAABNQAECn8kAAILAAkKOh2lWwCFAgALAAkKOh2lWwCFAgAAAA==.Totemlyawsum:BAAANQAECgYICwAAAA==.',
Tr='True:BAAANQAECgQIBgAAAA==.',
Tw='Twotone:BAAANQADCgcICAAAAA==.',
Ul='Ulkthar:BAAANQAECgUIBQABNQAFFAUICgAEAFUKAA==.',
Un='Unholyhammer:BAAANQABCgMIAQABNQAECggIDwABAAAAAA==.',
Va='Vacunamatata:BAAANQAECgQIBwAAAA==.Vaiyrnlol:BAACNQAFFH8LAAICAAQKMhUQCwA1AQACAAQKMhUQCwA1AQA1AAQKfysAAwIACgqRHWIhAOMCAAIACgqRHWIhAOMCAA0ABwo1H1stAKcBAAAA.Vanlin:BAABNQAECn8bAAImAAgKHBt0GwBcAgAmAAgKHBt0GwBcAgAAAA==.',
Ve='Vexxdr:BAABNQAECn83AAMmAAoKzhN5IQAcAgAmAAoKzhN5IQAcAgAFAAgK8xciJABjAQABNQAECgoKPQACALcjAA==.Vexxs:BAABNQAECn89AAMCAAoKtyPLCAA2AwACAAoKtyPLCAA2AwANAAMKxhTv6gDBAAAAAA==.',
Vo='Voidsuzu:BAABNQAECn84AAIdAAoKqBRIHQBqAgAdAAoKqBRIHQBqAgAAAA==.Vormedicus:BAAANQAECggIDgAAAA==.',
Vs='Vsaguzz:BAAANQADCggIEQABNQAECgoKNwAXAB8SAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQICQAAAA==.',
Wa='Waroo:BAAANQADCggICAAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Wickïdus:BAAANQABCggIEAAAAA==.Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECgQIDQAAAA==.',
Xa='Xaphelion:BAAANQAECgEIAQAAAA==.Xazio:BAABNQAECn83AAIeAAoKxhiuCAA7AgAeAAoKxhiuCAA7AgAAAA==.',
Yi='Yiang:BAABNQAECn8WAAIYAAcKChujJQD2AQAYAAcKChujJQD2AQAAAA==.',
Yl='Ylndrysa:BAABNQAECn9UAAImAAoKdhiqGAB5AgAmAAoKdhiqGAB5AgAAAA==.',
Ze='Zedrock:BAABNQAECn8xAAMRAAoKOSGYAQDXAgARAAoKOSGYAQDXAgAEAAIKWwv0IAE/AAAAAA==.Zeezu:BAAANQAECgMIAwAAAA==.Zekodian:BAAANQADCgQIBAAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAAANQAECggICgAAAA==.Zhitolight:BAAANQAECgMICAABNQAFFAQIBgAVACoXAA==.',
Zu='Zuro:BAABNQAECn8bAAIGAAgKkwcTwACDAQAGAAgKkwcTwACDAQAAAA==.',
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
