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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Unholy','Evoker-Preservation','DeathKnight-Frost','Shaman-Restoration','Druid-Restoration',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Ablestract:BAAANQADCgUIBQAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQADCgYIDAAAAA==.',
Ak='Aktzin:BAAANQADCgIIAgAAAA==.',
Al='Alex:BAAANQADCggIDgAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliwings:BAAANQAECgUIDQAAAA==.',
Am='Amarokk:BAAANQAECgEIAQAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
Ar='Arioch:BAAANQAECgEIAQAAAA==.',
As='Ashireg:BAAANQAECgcICAAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgQICgABAAAAAA==.',
Az='Azimondius:BAAANQAECgYIDgAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Belthora:BAAANQAECgQIBQAAAA==.Benry:BAAANQAECgUICQAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgYICgAAAA==.',
Bu='Bubblehëarth:BAAANQAECgEIAgAAAA==.Bulgestomper:BAAANQAECgQICQAAAA==.Bully:BAAANQAECgEIAQAAAA==.Burbuja:BAAANQADCgYICQAAAA==.Burrter:BAAANQADCgIIAgAAAA==.Buschgore:BAAANQADCgEIAQAAAA==.',
['Bá']='Bádoink:BAAANQADCgcIBwAAAA==.',
Ca='Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.',
Ce='Celessaria:BAAANQADCgYIEgAAAA==.Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Cherrypalaid:BAAANQAECgcIEQAAAA==.Chicntrl:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.',
Cl='Clingy:BAAANQADCgIIBAAAAA==.',
Co='Cobble:BAAANQAECgIIAgAAAA==.Colhap:BAAANQAECgYIDAAAAA==.Conjure:BAAANQADCgUIBQAAAA==.',
Cr='Creamsocket:BAAANQAECgMIBQAAAA==.',
Cu='Culligan:BAAANQAECgYIEQAAAA==.',
Cy='Cygwin:BAAANQAECgQIBgAAAA==.',
Da='Darklon:BAAANQAECgYIDwAAAA==.Datmage:BAAANQAECgEIAQAAAA==.',
De='Decomposed:BAAANQADCgQIAwAAAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECgQIBQAAAA==.Demunzz:BAAANQADCggIEwAAAA==.Destruction:BAAANQAECgQIBgAAAA==.Deverca:BAAANQADCgIIBAAAAA==.',
Di='Dithur:BAAANQADCgIIAgAAAA==.Divinespark:BAAANQAECgQIBgAAAA==.',
Do='Doinkbigs:BAAANQAECgMIAwAAAA==.Dolmant:BAAANQADCgcIBwAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAAANQAECgMIBQABNQAECgYIBQABAAAAAA==.',
Dr='Draethno:BAAANQADCgIIBgAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Druidrose:BAAANQADCgcIDgAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAAANQAECgEIAQAAAA==.',
['Dà']='Dàvë:BAAANQADCgcIBwABNQAECgUIBQABAAAAAA==.',
Ea='Eap:BAAANQADCggICgAAAA==.Eazye:BAAANQAECgcIEQAAAA==.',
Ed='Edgeffs:BAAANQAECgMIBQAAAA==.',
El='Elentiya:BAAANQAECgYICgAAAA==.Elphs:BAAANQAECgYIBgAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQADCgcIBwAAAA==.',
Fe='Felorc:BAAANQAECgQICwAAAA==.Fentun:BAAANQAECgYIDQAAAA==.',
Fo='Foulplay:BAAANQADCgQIBAAAAA==.',
Fr='Free:BAAANQAECgEIAQAAAA==.',
Ga='Gali:BAAANQABCgcIDgAAAA==.',
Ge='Gelektrael:BAAANQAECgQIBgAAAA==.Getchya:BAAANQADCggICwABNQAECgUIBQABAAAAAA==.',
Gh='Ghoostt:BAAANQAECgIIAgABNQAECgkJGwACABMaAA==.Ghostzz:BAABNQAECoEbAAICAAkJExp9HgCxAgACAAkJExp9HgCxAgAAAA==.',
Gl='Glzygldiator:BAAANQAECgIIBAAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQADCggIEgAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgQIBgABNQAECgcIEAABAAAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAAANQAECgYICwAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haschel:BAAANQADCgQIBAAAAA==.',
Ho='Holiecow:BAAANQAECgQIBwAAAA==.Hoshi:BAAANQADCgQIBAABNQAECggIGQADAH8lAA==.',
Hu='Hurtak:BAAANQAECgIIAgAAAA==.',
Hy='Hycisan:BAAANQAECgIIAwAAAA==.Hysteria:BAAANQADCgYIDQAAAA==.',
Ic='Icydoodad:BAAANQADCggIDwABNQAECgUIBQABAAAAAA==.',
Ik='Ikdutak:BAAANQADCgEIAQAAAA==.',
Il='Illusionwr:BAAANQADCgQIBwABNQAECggIEgABAAAAAA==.',
Ja='Jagerspell:BAAANQAECgYIDQAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAAANQAECgYICgAAAA==.',
Ka='Kaerina:BAAANQADCgcIEgAAAA==.Kanastra:BAAANQAECgQIBAABNQAECgYIDgABAAAAAA==.Kaylib:BAAANQAECgMIAwAAAA==.',
Ke='Kesi:BAAANQAECgMIAwAAAA==.',
Kh='Khaztharion:BAAANQADCgcIDgABNQAECgQIBQABAAAAAA==.Khendrick:BAAANQAECgIIAgAAAA==.',
Ki='Kittykatt:BAAANQAECgYIDQAAAA==.',
Kn='Knowledge:BAAANQAECgQIBgAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
Kr='Kraggo:BAAANQAECgYIEQAAAA==.Krimzin:BAAANQAECgUIBgABNQAECgkJHgAEAGUiAA==.',
La='Larsen:BAAANQAECgQIBgAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQADCggIDAAAAA==.',
Le='Leap:BAAANQADCggIGwAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lookadragon:BAAANQADCgQIBwAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Lunacy:BAAANQADCgcIFAAAAA==.',
Ly='Lynngosa:BAAANQAECgYIDgAAAA==.',
Ma='Magebob:BAAANQAECgEIAQAAAA==.Magisterium:BAAANQADCggIGwAAAA==.Mario:BAAANQABCgUIBQABNQADCgYIBgABAAAAAA==.Maulware:BAAANQADCgQIBAAAAA==.',
Me='Mentery:BAAANQADCgUIBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.',
Mi='Mightyguzz:BAAANQAECgYIDAAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAAANQAECgUICAAAAA==.Minimuffn:BAAANQAECgQIBgAAAA==.Misericordia:BAAANQAECgQIBQAAAA==.',
['Mø']='Møønchild:BAAANQAECgQIBAAAAA==.',
Na='Nanaish:BAAANQADCgUIBQAAAA==.Natë:BAABNQAECoEbAAIFAAkJzQ8dCAAMAgAFAAkJzQ8dCAAMAgAAAA==.',
Ne='Necrotalon:BAAANQADCggIEgAAAA==.Nemesia:BAAANQAECgQIBwAAAA==.Neonsunrise:BAAANQAECgcIEQAAAA==.',
Nh='Nharuna:BAAANQAECgYICwAAAA==.',
Ni='Nieloriel:BAAANQAECgQIBwAAAA==.Niykee:BAAANQAECgUICwAAAA==.',
No='Noboundss:BAAANQAECgUICgAAAA==.Noztra:BAAANQAECgUIDAAAAA==.',
Ns='Nsolant:BAAANQADCgYIBgAAAA==.',
Nu='Nukron:BAAANQADCggIEAAAAA==.',
Oh='Ohgr:BAAANQAECgYIDgAAAA==.Ohshifty:BAAANQAECgYIDgAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgQIBAAAAA==.',
Or='Orbsicles:BAAANQAECgQIBgAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQADCgUIBQAAAA==.Papitomyrey:BAAANQAECgMIAwABNQAECgUICgABAAAAAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIEQAAAA==.Pestílence:BAABNQAECoEfAAIGAAkJDyNRBACSAwAGAAkJDyNRBACSAwAAAA==.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQABCgQIBQAAAA==.Pooterdrip:BAAANQAECggIBwAAAA==.Powpow:BAAANQADCggICAAAAA==.',
Pr='Prejudice:BAAANQAECgQIBgAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAAANQAECgcIEgAAAA==.',
['Pû']='Pûff:BAAANQAECgYIDQAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Rainhoof:BAAANQAECgQIBgAAAA==.Ralneth:BAACNQAFFIEKAAIHAAUJthPtAgCoAQAHAAUJthPtAgCoAQA1AAQKgSEAAgcACQkoGAAMAHECAAcACQkoGAAMAHECAAAA.Rapala:BAAANQAECgIIAwAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECgIIAwABAAAAAA==.Raspútin:BAAANQAECgEIAQAAAA==.Rawdoinkers:BAAANQADCgYIDwAAAA==.',
Re='Renakir:BAAANQADCgEIAQAAAA==.Renly:BAAANQAECgIIBAAAAA==.Restoral:BAAANQAECgIIAQAAAA==.',
Ri='Riordan:BAAANQAECgQIBgAAAA==.',
Rj='Rjolz:BAABNQAECoEgAAMGAAkJOCTHAgCyAwAGAAkJOCTHAgCyAwAIAAEJqRzdRwBUAAAAAA==.',
Ro='Roflchopr:BAAANQAECgUIDQAAAA==.',
Sa='Sadcow:BAAANQAECgYICgAAAA==.Sandalfon:BAAANQADCgQIBAAAAA==.Sanleron:BAAANQADCggICAAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIAQAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQADCgYIBgAAAA==.',
Sh='Shadowclawz:BAAANQADCgIIBgAAAA==.Sharayse:BAAANQADCgYIEwAAAA==.Sharmee:BAAANQAECgIIAgAAAA==.Shmelverino:BAAANQABCggICQAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shogu:BAAANQAECgQIBgAAAA==.Sháde:BAAANQAECgQIBgAAAA==.',
Si='Simpmother:BAEANQAECgYIDQAAAA==.',
Sl='Slingablade:BAAANQAECgUIBwAAAA==.',
Sn='Sniffsniff:BAAANQAECgQIBgABNQAECggIGwAJADAmAA==.',
So='Solvi:BAAANQADCggIDgAAAA==.Sorá:BAAANQAECgQIBAABNQAECgcIEwABAAAAAA==.Soulbrand:BAAANQAECgMIBQAAAA==.',
Sp='Spellz:BAAANQADCgcIDAAAAA==.',
St='Stabathuh:BAAANQAECgUIBQAAAA==.Stabnskullz:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.Stacatta:BAAANQAECgEIAQAAAA==.Stinnky:BAAANQAFFAIIAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.Stoopidrood:BAAANQADCggIEAABNQAECgUIBQABAAAAAA==.Stoopidwarur:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.Stormclaw:BAAANQAECgQIBgAAAA==.',
Su='Sufiya:BAAANQAECgQIBQAAAA==.Suki:BAAANQAECgcIEAAAAA==.Sulfion:BAAANQABCgQIBAABNQADCgcIDAABAAAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYICgAAAA==.',
Sy='Sylveria:BAAANQAECgIIAwAAAA==.Sylvershadow:BAAANQADCgcIEgAAAA==.Syphon:BAAANQAECggIEAAAAA==.',
['Sý']='Sýrin:BAAANQADCgcIBwAAAA==.',
Ta='Tandarilada:BAAANQADCgMIAwAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAAANQAECgYIDQAAAA==.Thndrstrmlol:BAAANQADCgIIBgAAAA==.',
Ti='Titanic:BAAANQAECgEIAQAAAA==.',
To='Tomcruise:BAAANQAECgUICQAAAA==.Totemlyawsum:BAAANQAECgYICwAAAA==.',
Tr='True:BAAANQAECgIIBAAAAA==.',
Va='Vaiyrnlol:BAAANQAECgcIEAAAAA==.Vanlin:BAAANQAECgQIBgAAAA==.',
Ve='Vexxdr:BAAANQAECgQIBwABNQAECgcIEAABAAAAAA==.Vexxs:BAAANQAECgcIEAAAAA==.',
Vo='Voidsuzu:BAAANQAECgYIDAAAAA==.Vormedicus:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgMIAwAAAA==.',
Wa='Waroo:BAAANQADCggICAAAAA==.',
Wu='Wulffric:BAAANQADCgYICQAAAA==.',
Xa='Xazio:BAAANQAECgYIDAAAAA==.',
Yi='Yiang:BAAANQAECgUICgAAAA==.',
Yl='Ylndrysa:BAABNQAECoEZAAIKAAcJKBS7EwDjAQAKAAcJKBS7EwDjAQAAAA==.',
Ze='Zedrock:BAAANQAECggIEwAAAA==.Zeezu:BAAANQAECgMIAwAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAAANQADCggIEgAAAA==.Zhitolight:BAAANQAECgEIBAABNQAECgYIEAABAAAAAA==.',
Zu='Zuro:BAAANQAECgQIBgAAAA==.',
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
