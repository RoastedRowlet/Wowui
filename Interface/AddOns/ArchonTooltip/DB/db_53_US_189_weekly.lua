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

local lookup = {'Shaman-Restoration','Evoker-Devastation','Unknown-Unknown','Druid-Balance','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Priest-Discipline','DemonHunter-Havoc','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Evoker-Preservation','Warrior-Arms','Warrior-Protection','Shaman-Elemental','Rogue-Outlaw','DemonHunter-Devourer','Mage-Frost','Druid-Restoration','Druid-Feral','DeathKnight-Blood','Monk-Mistweaver','DemonHunter-Vengeance','Paladin-Protection',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Ablestract:BAAANQADCgUIBQAAAA==.',
Ac='Acid:BAAANQAECgEIAgAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgEIAQAAAA==.',
Ak='Akamma:BAAANQADCggIDgAAAA==.Aktzin:BAAANQADCgIIAgAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliwings:BAAANQAECgYIEwAAAA==.',
Am='Amarokk:BAAANQAECgEIAgAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
An='Ancestor:BAAANQADCgUICgAAAA==.',
Ar='Arioch:BAAANQAECgEIAQAAAA==.',
As='Ashireg:BAAANQAFFAMIAwAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgcIFwABACgWAA==.',
Az='Azimondius:BAABNQAECoEcAAICAAkKjxc2CgCfAgACAAkKjxc2CgCfAgAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQADCgYJBgABNQAECgUIBQADAAAAAA==.Belthora:BAAANQAECgQICQAAAA==.Benry:BAABNQAECoEZAAIEAAcKzx7XIwB4AgAEAAcKzx7XIwB4AgAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgYJDAAAAA==.',
Br='Brianjany:BAAANQAECgMIBAAAAA==.Browntotem:BAAANQADCgUIBQAAAA==.',
Bu='Bubblehëarth:BAAANQAECgEIAwAAAA==.Bulgestomper:BAAANQAECgYIDAAAAA==.Bully:BAAANQAECgYICwAAAA==.Burbuja:BAAANQAECgIIAwAAAA==.Burrter:BAAANQADCgIIAgAAAA==.Buschgore:BAAANQADCgQIBwAAAA==.',
['Bá']='Bádoink:BAAANQADCgcIBwAAAA==.',
Ca='Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.Castr:BAAANQAECgQIBAABNQAECgIIBAADAAAAAA==.',
Ce='Celessaria:BAAANQADCgYIEgAAAA==.Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Chargeantrot:BAAANQAECgEIAQABNQAECgcICAADAAAAAA==.Cherrypalaid:BAABNQAECoEZAAMFAAkKyBSGMgBfAgAFAAkKyBSGMgBfAgAGAAEKdAEMcgEbAAAAAA==.Chicntrl:BAAANQAECgcICAAAAA==.',
Cl='Clingy:BAAANQADCgUICQAAAA==.',
Co='Cobble:BAAANQAECgQICQAAAA==.Colhap:BAABNQAECoEgAAIHAAkKHCDvCQAeAwAHAAkKHCDvCQAeAwAAAA==.Conjure:BAAANQADCgYICgAAAA==.Corehammer:BAAANQADCgYIBwAAAA==.',
Cr='Creamsocket:BAAANQAECgQJBgAAAA==.Cru:BAAANQAECgQIBAAAAA==.',
Cu='Culligan:BAABNQAECoEpAAIIAAgKnRrmZgCAAgAIAAgKnRrmZgCAAgAAAA==.Cuttingcrew:BAAANQADCggICAAAAA==.',
Cy='Cygwin:BAAANQAECgYIEQAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAABNQAECoEZAAMJAAgKagq4VABXAQAJAAcKowq4VABXAQAKAAIKhwcDcwBhAAAAAA==.Datmage:BAAANQAECgEIAQAAAA==.',
De='Decomposed:BAAANQADCgMIAwAAAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECgcIDAAAAA==.Demunzz:BAAANQADCggIEwAAAA==.Destruction:BAAANQAECgUIEAAAAA==.Deverca:BAAANQADCgYJCgAAAA==.',
Di='Dithur:BAAANQADCgMJAwAAAA==.Divinespark:BAAANQAECgYIEAAAAA==.',
Do='Doinkbigs:BAAANQAECgYIDQAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Dooko:BAAANQAECgEIAQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAAANQAECgMICQABNQAECgcICAADAAAAAA==.',
Dr='Draethno:BAAANQADCgMIBwAAAA==.Drambush:BAAANQADCgMIAwAAAA==.Draqulen:BAAANQABCgYICQAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Drewsilla:BAAANQADCgIIAgAAAA==.Druidrose:BAAANQAECgMIAwAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAAANQAECgEIAQAAAA==.',
['Dà']='Dàvë:BAAANQADCgcIBwABNQAECgcIDQADAAAAAA==.',
Ea='Eap:BAAANQADCggIEQAAAA==.Eazye:BAABNQAECoEkAAIHAAgKZxzfEgCVAgAHAAgKZxzfEgCVAgAAAA==.',
Ed='Edgeffs:BAAANQAECgYIEAAAAA==.',
El='Elentiya:BAABNQAECoEZAAILAAgKcRsALwBrAgALAAgKcRsALwBrAgAAAA==.Elphs:BAAANQAECgcIEAAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQADCgcIBwAAAA==.',
Fa='Fabri:BAABNQAECoEYAAMMAAYKvCXICACeAQALAAYKvCWdQwARAgAMAAUKDSHICACeAQAAAA==.',
Fe='Felorc:BAAANQAECgUIEwAAAA==.Fenton:BAAANQAECgQIBAAAAA==.Fentun:BAABNQAECoEZAAIFAAgKqiZ0BQCNAwAFAAgKqiZ0BQCNAwAAAA==.',
Fo='Foulplay:BAAANQADCgQIBAAAAA==.',
Fr='Free:BAAANQAECgEIAQAAAA==.',
Ga='Gabacadabra:BAAANQABCgIIAgAAAA==.Gali:BAAANQABCgcIFAAAAA==.',
Ge='Gelektrael:BAAANQAECgYIEQAAAA==.Getchya:BAAANQAECgQIBQABNQAECgcIDQADAAAAAA==.',
Gh='Ghoostt:BAAANQAECgUICAABNQAECgkJJQAGAMcdAA==.Ghostzz:BAABNQAECoElAAIGAAkKxx3uKADqAgAGAAkKxx3uKADqAgAAAA==.',
Gl='Gloríous:BAAANQADCggICwABNQAECgUIDAADAAAAAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQAECgUICQAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgUICAAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAAANQAECgYIDgAAAA==.Haldire:BAAANQABCgQIBAAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haruto:BAAANQADCggICAAAAA==.Haschel:BAAANQADCgcICgAAAA==.Haunterx:BAAANQAECgQIBAAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAAANQAECgYIEgAAAA==.Hoshi:BAAANQADCgQIBAABNQAECgkJKAAHAK8kAA==.',
Hu='Hurtak:BAAANQAECgUICgAAAA==.',
Hy='Hycisan:BAAANQAECgUIDAAAAA==.Hysteria:BAAANQAECgIIAgAAAA==.',
Ic='Icydoodad:BAAANQADCggIFwABNQAECgcIDQADAAAAAA==.',
Ik='Ikdutak:BAAANQAECgUIBQAAAA==.',
Il='Illusionwr:BAAANQADCgQIBwABNQAECgkKJAANAFsdAA==.',
Ja='Jagerspell:BAABNQAECoEeAAMOAAgK3iJIBwDyAgAOAAgKOCFIBwDyAgAPAAMKIyQFQABBAQAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAAANQAECgYIDAAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAAANQAECgQIBwAAAA==.Kanastra:BAAANQAECgYIDwABNQAECgkJHAACAI8XAA==.Karraa:BAAANQADCgYJBgABNQAECgQIBwADAAAAAA==.Kaylib:BAAANQAECgUIDQAAAA==.',
Ke='Kesi:BAAANQAECgMJAwAAAA==.',
Kh='Khaztharion:BAAANQADCgcIDgABNQAECgUIDgADAAAAAA==.Khendrick:BAAANQAECgYICwAAAA==.',
Ki='Kittykatt:BAABNQAECoEYAAIEAAgKYxksKwBAAgAEAAgKYxksKwBAAgAAAA==.',
Kn='Knowledge:BAAANQAECgYIEQAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECgcIFQAQAEIUAA==.',
Kr='Kraggo:BAABNQAECoEnAAMRAAkKPxleIQDLAgARAAkKPxleIQDLAgASAAIKZgncWQBfAAAAAA==.Krimzin:BAAANQAECgcICwABNQAFFAQICQATALsWAA==.',
['Kí']='Kíllerwolf:BAAANQAECgEIAQAAAA==.',
La='Larsen:BAAANQAECgYIEQAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQAECgUIBQAAAA==.',
Le='Leap:BAAANQAECgQIBwAAAA==.Legbah:BAAANQADCgYIBgABNQAECgcIDQADAAAAAA==.',
Li='Lightmare:BAAANQADCgYIBgAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lookadragon:BAAANQAECgUIBwAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAQADAAAAAA==.Lunacy:BAAANQAECgIIAgAAAA==.',
Ly='Lynngosa:BAABNQAECoEfAAIUAAgK9xCjGQDqAQAUAAgK9xCjGQDqAQAAAA==.',
Ma='Magebob:BAAANQAECgMIAwAAAA==.Magisterium:BAAANQAECgEIAQAAAA==.Mario:BAAANQABCgUIBQABNQADCgYIBgADAAAAAA==.Maulware:BAAANQADCgQIBwAAAA==.',
Me='Meingaree:BAAANQABCgcICgAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.',
Mi='Mightyguzz:BAABNQAECoEaAAIVAAcKoghHowBfAQAVAAcKoghHowBfAQAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAAANQAECgYIDgAAAA==.Minimuffn:BAAANQAECgYIEQAAAA==.Misericordia:BAAANQAECgYIDwAAAA==.',
['Mø']='Møønchild:BAAANQAECgQIBwAAAA==.',
Na='Nanaish:BAAANQAECgIIAwAAAA==.Natë:BAABNQAECoErAAIWAAkK0BJcDQAEAgAWAAkK0BJcDQAEAgAAAA==.',
Ne='Necrotalon:BAAANQAECgUIBQAAAA==.Nemesia:BAABNQAECoEVAAMQAAcKQhQKEgAsAQAVAAcK1RKugwC8AQAQAAUKKxAKEgAsAQAAAA==.Neonsunrise:BAABNQAECoEkAAIHAAgKph+JDgDWAgAHAAgKph+JDgDWAgAAAA==.',
Nh='Nharuna:BAABNQAECoEYAAITAAgKMg/DWAAXAgATAAgKMg/DWAAXAgAAAA==.',
Ni='Nieloriel:BAAANQAECgQIBwAAAA==.Nimbus:BAAANQAECgIIBAABNQAFFAYIDgAXAEEZAA==.Niykee:BAABNQAECoEaAAQPAAcKQCEyHQA+AgAPAAYK4yEyHQA+AgAYAAUKOxsCDABrAQAOAAEKSAj5RQA4AAAAAA==.',
No='Noboundss:BAABNQAECoEWAAMNAAgKJBg8IABPAgANAAgKgRc8IABPAgAZAAQKjhlYPAATAQAAAA==.Noztra:BAABNQAECoEhAAMIAAcKGAtG0QCSAQAIAAcKGAtG0QCSAQAaAAEKqhKgNgA6AAAAAA==.',
Ns='Nsolant:BAAANQAECgUICQAAAA==.',
Nu='Nubsy:BAAANQAECgEIAQAAAA==.Nuker:BAAANQADCgUIBQAAAA==.Nukron:BAAANQADCggIEAAAAA==.',
Oh='Ohgr:BAAANQAECgYIEwAAAA==.Ohshifty:BAABNQAECoEgAAMEAAgKwhVcLAA2AgAEAAgKwhVcLAA2AgAbAAIK5gGDWAA8AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgUJCQAAAA==.',
Or='Orbsicles:BAAANQAECgYIEQAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQADCgUIBQAAAA==.Papitomyrey:BAAANQAECgMIAwABNQAECgcIEwADAAAAAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAABNQAECoEqAAIJAAkKVyR5AwCoAwAJAAkKVyR5AwCoAwAAAA==.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQABCgQIBQAAAA==.Pooter:BAAANQAECggIDwAAAA==.Powpow:BAAANQAECgcIDgAAAA==.',
Pr='Prejudice:BAAANQAECgYIEQAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAABNQAECoEiAAMbAAgKowzEJACbAQAbAAgKowzEJACbAQAcAAcKKQ24EACHAQAAAA==.',
['Pû']='Pûff:BAABNQAECoEdAAIUAAgKrxsaDwCKAgAUAAgKrxsaDwCKAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQAECgEIAQAAAA==.Rainhoof:BAAANQAECgYIEQAAAA==.Ralneth:BAACNQAFFIEUAAIUAAYKNRQRBAD9AQAUAAYKNRQRBAD9AQA1AAQKgScAAhQACQooGHASAFcCABQACQooGHASAFcCAAAA.Rapala:BAAANQAECgYIDgAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECgYIDgADAAAAAA==.Raspútin:BAAANQAECgMIAwAAAA==.Rawdoinkers:BAAANQADCgYIGgAAAA==.Rawkfice:BAAANQADCgQIBwAAAA==.',
Re='Renakir:BAAANQADCgEIAQAAAA==.Renly:BAAANQAECgYIDwAAAA==.Restoral:BAAANQAECgIIAQAAAA==.',
Ri='Riordan:BAAANQAECgQICwAAAA==.Rivvetear:BAAANQADCgIIAgAAAA==.',
Rj='Rjolz:BAACNQAFFIEGAAIJAAMK1h/OCAAHAQAJAAMK1h/OCAAHAQA1AAQKgTEAAwkACQo7Jo4BANYDAAkACQo7Jo4BANYDAAoABgryHbApAOwBAAAA.',
Ro='Roflchopr:BAABNQAECoEWAAIGAAcKyRCzjwCbAQAGAAcKyRCzjwCbAQAAAA==.',
Sa='Sadcow:BAABNQAECoEbAAIXAAgK3BpFLwB+AgAXAAgK3BpFLwB+AgAAAA==.Sandalfon:BAAANQADCgYICQAAAA==.Sanleron:BAAANQAECgcICwAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIAwAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQADCgYICAAAAA==.',
Sh='Shadowclawz:BAAANQADCgUICwAAAA==.Sharayse:BAAANQADCgYIEwAAAA==.Sharmee:BAAANQAECgYIDgAAAA==.Shmelverino:BAAANQABCggIDAAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shogu:BAAANQAECgYIEQAAAA==.Sháde:BAAANQAECgYIEQAAAA==.',
Si='Simpmother:BAEBNQAECoEdAAIRAAgKhQxUaQDLAQARAAgKhQxUaQDLAQAAAA==.',
Sl='Slingablade:BAABNQAECoEXAAIZAAgKiRSJHAA4AgAZAAgKiRSJHAA4AgAAAA==.',
Sn='Sniffsniff:BAAANQAECgYICQABNQAFFAMIBwABAM0mAA==.',
So='Solvi:BAAANQAECgIJAgAAAA==.Sorá:BAAANQAECgYIEQABNQAECgkJJQAdAD4SAA==.Soulbrand:BAAANQAECgMIBQAAAA==.',
Sp='Spellz:BAAANQADCgcJDAABNQAECgIIAgADAAAAAA==.',
St='Stabathuh:BAAANQAECgcIDQAAAA==.Stabnskullz:BAAANQAECgQJBAABNQAECgcIDAADAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIJAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECgcIDQADAAAAAA==.Stoopidlock:BAAANQADCggIEgABNQAECgcIDQADAAAAAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECgcIDQADAAAAAA==.Stoopidrood:BAAANQADCggIFAABNQAECgcIDQADAAAAAA==.Stoopidwarur:BAAANQADCgcIDQABNQAECgcIDQADAAAAAA==.Stormclaw:BAAANQAECgYIEQAAAA==.Styne:BAAANQADCggICAABNQAECggIGwAXANwaAA==.',
Su='Sufiya:BAAANQAECgUIDgAAAA==.Suki:BAABNQAECoEkAAIeAAgKMB8UCgC1AgAeAAgKMB8UCgC1AgAAAA==.Sulfion:BAAANQAECgIIAgAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYJCgAAAA==.',
Sy='Sylveria:BAAANQAECgIIAwAAAA==.Sylvershadow:BAAANQAECgEIAQAAAA==.Syphon:BAABNQAECoEjAAMfAAkKHx0gAwDyAgAfAAgKkSAgAwDyAgANAAIKVQElgAAMAAAAAA==.',
['Sý']='Sýrin:BAAANQADCggJCgAAAA==.',
Ta='Tandarilada:BAAANQADCgMJAwAAAA==.Tanfer:BAAANQADCggICQAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECoEdAAIVAAgK9BnFTgBeAgAVAAgK9BnFTgBeAgAAAA==.Thndrstrmlol:BAAANQADCgYIDAAAAA==.',
Ti='Titanic:BAAANQAECgQIBAAAAA==.',
To='Tomcruise:BAAANQAECgcIEQAAAA==.Totemlyawsum:BAAANQAECgYICwAAAA==.',
Tr='True:BAAANQAECgIIBAAAAA==.',
Un='Unholyhammer:BAAANQABCgMIAQABNQAECgcIDAADAAAAAA==.',
Va='Vaiyrnlol:BAABNQAECoEYAAIBAAkKzh3kEwD/AgABAAkKzh3kEwD/AgAAAA==.Vanlin:BAAANQAECgYIDAAAAA==.',
Ve='Vexxdr:BAABNQAECoEcAAMbAAkKbg1FHQDwAQAbAAkKbg1FHQDwAQAEAAQKXhUqWgAYAQABNQAECgkJIAABANIaAA==.Vexxs:BAABNQAECoEgAAIBAAkK0hpRFgDvAgABAAkK0hpRFgDvAgAAAA==.',
Vo='Voidsuzu:BAABNQAECoEbAAIZAAgKGA4iJADrAQAZAAgKGA4iJADrAQAAAA==.Vormedicus:BAAANQADCgcIDQABNQAECgMIAwADAAAAAA==.',
Vs='Vsaguzz:BAAANQADCgEJAQABNQAECgcIGgAVAKIIAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQICQAAAA==.',
Wa='Waroo:BAAANQADCggICAAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECgIIAwAAAA==.',
Xa='Xaphelion:BAAANQADCggIEAAAAA==.Xazio:BAABNQAECoEaAAIgAAcKdRN2IACFAQAgAAcKdRN2IACFAQAAAA==.',
Yi='Yiang:BAAANQAECgUIEgAAAA==.',
Yl='Ylndrysa:BAABNQAECoElAAIbAAgKqxNoGwAIAgAbAAgKqxNoGwAIAgAAAA==.',
Ze='Zedrock:BAABNQAECoEYAAIaAAgKhSDRAwDAAgAaAAgKhSDRAwDAAgAAAA==.Zeezu:BAAANQAECgMIAwAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAAANQAECgUICQAAAA==.Zhitolight:BAAANQAECgEIBAABNQAECggICAADAAAAAA==.',
Zu='Zuro:BAAANQAECgYIEAAAAA==.',
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
