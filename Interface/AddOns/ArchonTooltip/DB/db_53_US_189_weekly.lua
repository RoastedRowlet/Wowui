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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Priest-Shadow','Mage-Arcane','Paladin-Holy','Paladin-Retribution','DemonHunter-Havoc','Rogue-Subtlety','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','Druid-Feral','DeathKnight-Frost','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','DemonHunter-Vengeance','Warrior-Arms','Mage-Frost','Priest-Holy',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Ablestract:BAAANQADCgUIBQAAAA==.',
Ac='Acid:BAAANQAECgEJAgAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgEIAQAAAA==.',
Ak='Akamma:BAAANQADCgYIBgAAAA==.Aktzin:BAAANQADCgIIAgAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliwings:BAAANQAECgYJEwAAAA==.',
Am='Amarokk:BAAANQAECgEIAgAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
Ar='Arioch:BAAANQAECgEIAQAAAA==.',
As='Ashireg:BAAANQAFFAMIAwAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgQIDgABAAAAAA==.',
Az='Azimondius:BAABNQAECoEYAAICAAgK1ha5CwBiAgACAAgK1ha5CwBiAgAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQADCgYJBgABNQAECgMIAwABAAAAAA==.Belthora:BAAANQAECgQIBwAAAA==.Benry:BAAANQAECgYIDwAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAABNQAECgUICgABAAAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgYJDAAAAA==.',
Br='Brianjany:BAAANQAECgMIBAAAAA==.Browntotem:BAAANQADCgUIBQAAAA==.',
Bu='Bubblehëarth:BAAANQAECgEIAwAAAA==.Bulgestomper:BAAANQAECgQICQAAAA==.Bully:BAAANQAECgQJBQAAAA==.Burbuja:BAAANQAECgEJAQAAAA==.Burrter:BAAANQADCgIIAgAAAA==.Buschgore:BAAANQADCgEIAQAAAA==.',
['Bá']='Bádoink:BAAANQADCgcIBwAAAA==.',
Ca='Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.',
Ce='Celessaria:BAAANQADCgYIEgAAAA==.Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Cherrypalaid:BAAANQAECgcIEgAAAA==.Chicntrl:BAAANQAECgcJBwAAAA==.',
Cl='Clingy:BAAANQADCgUICQAAAA==.',
Co='Cobble:BAAANQAECgIIAgAAAA==.Colhap:BAABNQAECoEaAAIDAAkK7xuICwDtAgADAAkK7xuICwDtAgAAAA==.Conjure:BAAANQADCgUJBQAAAA==.',
Cr='Creamsocket:BAAANQAECgQJBgAAAA==.',
Cu='Culligan:BAABNQAECoEfAAIEAAgKyBiUYgBnAgAEAAgKyBiUYgBnAgAAAA==.',
Cy='Cygwin:BAAANQAECgUJCwAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAAANQAECgcJEQAAAA==.Datmage:BAAANQAECgEIAQAAAA==.',
De='Decomposed:BAAANQADCgQIAwAAAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECgQIBQAAAA==.Demunzz:BAAANQADCggIEwAAAA==.Destruction:BAAANQAECgUJCwAAAA==.Deverca:BAAANQADCgYJCgAAAA==.',
Di='Dithur:BAAANQADCgMJAwAAAA==.Divinespark:BAAANQAECgUJCgAAAA==.',
Do='Doinkbigs:BAAANQAECgQJBwAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAAANQAECgMIBwABNQAECgcJBwABAAAAAA==.',
Dr='Draethno:BAAANQADCgMIBwAAAA==.Drambush:BAAANQADCgEIAQAAAA==.Draqulen:BAAANQABCgYICAAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Druidrose:BAAANQADCgcJFAAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAAANQAECgEIAQAAAA==.',
['Dà']='Dàvë:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
Ea='Eap:BAAANQADCggICgAAAA==.Eazye:BAABNQAECoEcAAIDAAgKlxnNEQCDAgADAAgKlxnNEQCDAgAAAA==.',
Ed='Edgeffs:BAAANQAECgUJCgAAAA==.',
El='Elentiya:BAAANQAECgcJEQAAAA==.Elphs:BAAANQAECgcJDQAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQADCgcIBwAAAA==.',
Fe='Felorc:BAAANQAECgUJDwAAAA==.Fenton:BAAANQABCgMIAwABNQABCgYIDAABAAAAAA==.Fentun:BAABNQAECoEWAAIFAAgKpyYSBACSAwAFAAgKpyYSBACSAwAAAA==.',
Fo='Foulplay:BAAANQADCgQIBAAAAA==.',
Fr='Free:BAAANQAECgEIAQAAAA==.',
Ga='Gabacadabra:BAAANQABCgIIAgAAAA==.Gali:BAAANQABCgcJDgAAAA==.',
Ge='Gelektrael:BAAANQAECgUJCwAAAA==.Getchya:BAAANQAECgQIBQABNQAECgYICwABAAAAAA==.',
Gh='Ghoostt:BAAANQAECgIIAgABNQAECgkJHgAGAEYcAA==.Ghostzz:BAABNQAECoEeAAIGAAkKRhy1KgCyAgAGAAkKRhy1KgCyAgAAAA==.',
Gl='Gloríous:BAAANQADCgMJAwABNQAECgQJBwABAAAAAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQAECgQJBAAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgUICAABNQAECgcIEQABAAAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAAANQAECgYJDgAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haschel:BAAANQADCgcICgAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAAANQAECgYIDQAAAA==.Hoshi:BAAANQADCgQIBAABNQAECggIIQADAH8lAA==.',
Hu='Hurtak:BAAANQAECgQJBgAAAA==.',
Hy='Hycisan:BAAANQAECgQIBwAAAA==.Hysteria:BAAANQAECgIIAgAAAA==.',
Ic='Icydoodad:BAAANQADCggIDwABNQAECgYICwABAAAAAA==.',
Ik='Ikdutak:BAAANQAECgMIAwAAAA==.',
Il='Illusionwr:BAAANQADCgQIBwABNQAECgkKHwAHADMdAA==.',
Ja='Jagerspell:BAABNQAECoEWAAMIAAgKQSDgBgDuAgAIAAgKQSDgBgDuAgAJAAIKyh1QSQCsAAAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAAANQAECgYIDAAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAAANQAECgMJAwAAAA==.Kanastra:BAAANQAECgUJCQABNQAECggIGAACANYWAA==.Karraa:BAAANQADCgYJBgABNQAECgMJAwABAAAAAA==.Kaylib:BAAANQAECgUICAAAAA==.',
Ke='Kesi:BAAANQAECgMJAwAAAA==.',
Kh='Khaztharion:BAAANQADCgcIDgABNQAECgQICQABAAAAAA==.Khendrick:BAAANQAECgMJBQAAAA==.',
Ki='Kittykatt:BAAANQAECgYJEwAAAA==.',
Kn='Knowledge:BAAANQAECgUJCwAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECgcIDgABAAAAAA==.',
Kr='Kraggo:BAABNQAECoEZAAMKAAcKKhsGOAA9AgAKAAcKKhsGOAA9AgALAAIKZgniUgBjAAAAAA==.Krimzin:BAAANQAECgcJCgABNQAFFAMIBQAMAEUVAA==.',
La='Larsen:BAAANQAECgUJCwAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQADCggIDAAAAA==.',
Le='Leap:BAAANQAECgMJAwAAAA==.',
Li='Lightmare:BAAANQADCgYIBgAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lookadragon:BAAANQAECgIJAgAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Lunacy:BAAANQAECgIIAgAAAA==.',
Ly='Lynngosa:BAABNQAECoEXAAINAAgKHg+aFgDkAQANAAgKHg+aFgDkAQAAAA==.',
Ma='Magebob:BAAANQAECgIJAgAAAA==.Magisterium:BAAANQADCggJHgAAAA==.Mario:BAAANQABCgUIBQABNQADCgYIBgABAAAAAA==.Maulware:BAAANQADCgQJBwAAAA==.',
Me='Meingaree:BAAANQABCgUJBwAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.',
Mi='Mightyguzz:BAAANQAECgcIEwAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAAANQAECgUJDQAAAA==.Minimuffn:BAAANQAECgUJCwAAAA==.Misericordia:BAAANQAECgQICQAAAA==.',
['Mø']='Møønchild:BAAANQAECgQJBAAAAA==.',
Na='Nanaish:BAAANQAECgEJAQAAAA==.Natë:BAABNQAECoEjAAIOAAkKnxL9CQAaAgAOAAkKnxL9CQAaAgAAAA==.',
Ne='Necrotalon:BAAANQADCggIEgAAAA==.Nemesia:BAAANQAECgcIDgAAAA==.Neonsunrise:BAABNQAECoEcAAIDAAgKBh5cDQDLAgADAAgKBh5cDQDLAgAAAA==.',
Nh='Nharuna:BAAANQAECgYJEQAAAA==.',
Ni='Nieloriel:BAAANQAECgQIBwAAAA==.Nimbus:BAAANQAECgIIAgABNQAFFAUICAAPALYTAA==.Niykee:BAAANQAECgYIEQAAAA==.',
No='Noboundss:BAAANQAECgUIDgAAAA==.Noztra:BAAANQAECgYJEgAAAA==.',
Ns='Nsolant:BAAANQAECgQJBAAAAA==.',
Nu='Nukron:BAAANQADCggIEAAAAA==.',
Oh='Ohgr:BAAANQAECgYIEwAAAA==.Ohshifty:BAABNQAECoEZAAMQAAgKchR8JwAtAgAQAAgKchR8JwAtAgARAAIK5gFgSgA/AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgUJCQAAAA==.',
Or='Orbsicles:BAAANQAECgYIDAAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQADCgUIBQAAAA==.Papitomyrey:BAAANQAECgMIAwABNQAECgcJEQABAAAAAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAABNQAECoEiAAISAAkKDyMkBgCAAwASAAkKDyMkBgCAAwAAAA==.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQABCgQIBQAAAA==.Pooter:BAAANQAECggJDwAAAA==.Powpow:BAAANQAECgYIBgAAAA==.',
Pr='Prejudice:BAAANQAECgUJCwAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAABNQAECoEdAAMRAAgKdAzaHQCnAQARAAgKdAzaHQCnAQATAAcKKQ3pDACXAQAAAA==.',
['Pû']='Pûff:BAABNQAECoEWAAINAAgKJhszDQCIAgANAAgKJhszDQCIAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQADCggICAAAAA==.Rainhoof:BAAANQAECgUJCwAAAA==.Ralneth:BAACNQAFFIEPAAINAAUKyRYFBAC7AQANAAUKyRYFBAC7AQA1AAQKgSQAAg0ACQooGHQPAGICAA0ACQooGHQPAGICAAAA.Rapala:BAAANQAECgUJCAAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECgUJCAABAAAAAA==.Raspútin:BAAANQAECgEIAQAAAA==.Rawdoinkers:BAAANQADCgYIFAAAAA==.Rawkfice:BAAANQADCgMIBAAAAA==.',
Re='Renakir:BAAANQADCgEIAQAAAA==.Renly:BAAANQAECgUJCQAAAA==.Restoral:BAAANQAECgIIAQAAAA==.',
Ri='Riordan:BAAANQAECgQJCAAAAA==.Rivvetear:BAAANQADCgIJAgAAAA==.',
Rj='Rjolz:BAABNQAECoEpAAMSAAkKdCR+AgDEAwASAAkKdCR+AgDEAwAUAAYK8h3fHQANAgAAAA==.',
Ro='Roflchopr:BAAANQAECgYIEQAAAA==.',
Sa='Sadcow:BAAANQAECgcJEQAAAA==.Sandalfon:BAAANQADCgQIBAAAAA==.Sarith:BAAANQADCgcJBwAAAA==.Sarloz:BAAANQAECgEIAgAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQADCgYIBgAAAA==.',
Sh='Shadowclawz:BAAANQADCgUJCwAAAA==.Sharayse:BAAANQADCgYIEwAAAA==.Sharmee:BAAANQAECgYICAAAAA==.Shmelverino:BAAANQABCggIDAAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shogu:BAAANQAECgUJCwAAAA==.Sháde:BAAANQAECgUJCwAAAA==.',
Si='Simpmother:BAEBNQAECoEWAAIKAAgKZgyRUgDXAQAKAAgKZgyRUgDXAQAAAA==.',
Sl='Slingablade:BAAANQAECgcJDgAAAA==.',
Sn='Sniffsniff:BAAANQAECgQJBgABNQAECggJHgAVAEcmAA==.',
So='Solvi:BAAANQAECgIJAgAAAA==.Sorá:BAAANQAECgUICQABNQAECggIHAAWAGIQAA==.Soulbrand:BAAANQAECgMIBQAAAA==.',
Sp='Spellz:BAAANQADCgcJDAAAAA==.',
St='Stabathuh:BAAANQAECgYICwAAAA==.Stabnskullz:BAAANQAECgQJBAABNQAECgQIBQABAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIJAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Stoopidlock:BAAANQADCgcICgABNQAECgYICwABAAAAAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Stoopidrood:BAAANQADCggIEAABNQAECgYICwABAAAAAA==.Stoopidwarur:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Stormclaw:BAAANQAECgUJCwAAAA==.',
Su='Sufiya:BAAANQAECgQICQAAAA==.Suki:BAABNQAECoEcAAIXAAgKjR17CAC0AgAXAAgKjR17CAC0AgAAAA==.Sulfion:BAAANQABCgQIBAABNQADCgcJDAABAAAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYJCgAAAA==.',
Sy='Sylveria:BAAANQAECgIIAwAAAA==.Sylvershadow:BAAANQADCggJGgAAAA==.Syphon:BAABNQAECoEbAAMYAAkKghoNAwDIAgAYAAgKoR0NAwDIAgAHAAIKVQEabAAMAAAAAA==.',
['Sý']='Sýrin:BAAANQADCggJCgAAAA==.',
Ta='Tandarilada:BAAANQADCgMJAwAAAA==.Tanfer:BAAANQADCgcIBwAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECoEWAAIZAAgKQRnZQgBcAgAZAAgKQRnZQgBcAgAAAA==.Thndrstrmlol:BAAANQADCgYJDAAAAA==.',
Ti='Titanic:BAAANQAECgQIBAAAAA==.',
To='Tomcruise:BAAANQAECgYJDwAAAA==.Totemlyawsum:BAAANQAECgYICwAAAA==.',
Tr='True:BAAANQAECgIIBAAAAA==.',
Va='Vaiyrnlol:BAAANQAECgcIEgABNQAECgkJHAAEAL0ZAA==.Vanlin:BAAANQAECgQJBgAAAA==.',
Ve='Vexxdr:BAAANQAECgcIDgABNQAECgkJFwAVAAQZAA==.Vexxs:BAABNQAECoEXAAIVAAkKBBn7EwDmAgAVAAkKBBn7EwDmAgAAAA==.',
Vo='Voidsuzu:BAAANQAECgcJEwAAAA==.Vormedicus:BAAANQADCgcICQABNQAECgEIAQABAAAAAA==.',
Vs='Vsaguzz:BAAANQADCgEJAQABNQAECgcIEwABAAAAAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQIBQAAAA==.',
Wa='Waroo:BAAANQADCggICAAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECgEJAQAAAA==.',
Xa='Xaphelion:BAAANQADCggICAAAAA==.Xazio:BAAANQAECgcJEwAAAA==.',
Yi='Yiang:BAAANQAECgUJDgAAAA==.',
Yl='Ylndrysa:BAABNQAECoEZAAIRAAcKKBRZGgDUAQARAAcKKBRZGgDUAQAAAA==.',
Ze='Zedrock:BAABNQAECoEYAAIaAAgKhSBKAgDpAgAaAAgKhSBKAgDpAgAAAA==.Zeezu:BAAANQAECgMIAwAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAAANQAECgQJBAAAAA==.Zhitolight:BAAANQAECgEIBAABNQAECggIGQAbAEojAA==.',
Zu='Zuro:BAAANQAECgUJCgAAAA==.',
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
