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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aassvik:BAAANQADCgYICwAAAA==.',
Ab='Absolute:BAAANQAECgYICQAAAA==.',
Ac='Achieved:BAAANQAECgQIBAAAAA==.Achievsome:BAAANQAECgcICgAAAA==.',
Ad='Adorabull:BAAANQADCgEIAQAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Ah='Ahnruun:BAAANQADCgUIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alessandro:BAAANQADCgUIBwAAAA==.Aliengrey:BAAANQADCgMIAwAAAA==.Alonsusfaol:BAAANQAECgEIAQAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.',
Am='Amane:BAAANQAECgUIBwAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.',
An='Annya:BAAANQAECgEIAQAAAA==.',
Ar='Arkanis:BAAANQAECgIIAgAAAA==.Armament:BAAANQAECgEIAgABNQAECgMIAwABAAAAAA==.',
As='Ashleymarion:BAAANQADCgIIAgAAAA==.',
Au='Aurafiora:BAAANQAECgIIAgAAAA==.Aurius:BAAANQADCggIDgAAAA==.',
Av='Avalancha:BAAANQADCgEIAQAAAA==.Avinoch:BAAANQADCgUICAAAAA==.',
Ax='Axon:BAAANQAECgIIAgAAAA==.',
Ay='Aynhillbeads:BAAANQADCgcIDQAAAA==.',
Az='Azekor:BAAANQADCgYIBgAAAA==.Azenroth:BAAANQADCggICQAAAA==.Azureth:BAAANQAECgEIAQAAAA==.',
Ba='Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAAANQAECgEIAQAAAA==.Barnicas:BAAANQADCgMIAwAAAA==.Bartholomäus:BAAANQADCgMIAwAAAA==.',
Be='Beezlebumon:BAAANQAECgIIAgAAAA==.Bewater:BAAANQAECgMIAwAAAA==.',
Bl='Blóðugrgríma:BAAANQADCgYICwAAAA==.',
Bo='Bobabear:BAAANQADCgYIFgAAAA==.Bonersimpsun:BAAANQADCggIBwAAAA==.Boombastic:BAAANQADCgYIBwAAAA==.Boomclap:BAAANQAECgQIBgAAAA==.',
Bp='Bpbreezy:BAAANQAECgcICwAAAA==.',
Br='Bracknor:BAAANQADCgYIBgAAAA==.Braknight:BAAANQADCgYIBgAAAA==.Brandonb:BAAANQAECgQIBQAAAA==.Brandonw:BAAANQADCgUICAAAAA==.Bredock:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.Brotem:BAAANQADCggIDgAAAA==.Brutalisto:BAAANQADCgUICAAAAA==.Brynnbramble:BAAANQADCgYIBgAAAA==.',
By='Bysokar:BAAANQAECgMIAwAAAA==.',
Ca='Cainfortea:BAAANQADCgQIBwAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Calipal:BAAANQADCgQICAAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Catalinasham:BAAANQAFFAIIAgAAAA==.Catalïna:BAAANQADCgcIBwABNQAFFAIIAgABAAAAAA==.Cazadore:BAAANQADCggICAAAAA==.',
Ce='Celebrimbjor:BAAANQADCgYICgAAAA==.',
Ch='Challengerz:BAAANQADCgYIBgAAAA==.Charliehorse:BAAANQADCgMIAwAAAA==.Chopper:BAAANQADCggIDwAAAA==.',
Ci='Cinderlily:BAAANQADCgUIBwAAAA==.',
Co='Conflagrate:BAAANQAECgQIBQAAAA==.Connery:BAAANQADCgMIBAAAAA==.',
Cp='Cptcrushingb:BAAANQADCgMIAwAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQADCgYICgAAAA==.Criturrpants:BAAANQADCgYIBgAAAA==.',
Cy='Cynnå:BAAANQADCggIDQAAAA==.Cynthea:BAAANQADCgMIAwAAAA==.Cyp:BAAANQAECgQIBgAAAA==.',
Da='Dababycar:BAAANQADCggICAAAAA==.Dabbyduck:BAAANQAECgcIDAAAAA==.Danifru:BAAANQADCgYICQAAAA==.',
De='Deadincide:BAEANQADCggIDwAAAA==.Deadstasheo:BAAANQAECgQIBQAAAA==.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAAANQADCgYICwAAAA==.Deezmonz:BAAANQABCgEIAQABNQAECgQIBQABAAAAAA==.Delik:BAAANQADCgEIAQAAAA==.Demonarch:BAAANQADCgUIBQAAAA==.Demonlordmeh:BAAANQADCgUIBQAAAA==.Deneol:BAAANQAECgEIAQAAAA==.Destrogen:BAAANQAECgEIAQAAAA==.Desìre:BAAANQADCgEIAQAAAA==.',
Di='Dirty:BAAANQADCgYICgAAAA==.',
Dk='Dksura:BAAANQADCgYICQAAAA==.',
Do='Doomshield:BAAANQADCgYICgAAAA==.',
Dr='Dracodeez:BAAANQADCggIDgAAAA==.Driretlan:BAAANQADCgYIBgAAAA==.Druss:BAAANQAECgMIAwAAAA==.',
Em='Emilianaluz:BAAANQADCgQIBAAAAA==.',
En='Endeavor:BAAANQADCgcIDAAAAA==.',
Eq='Equâs:BAAANQADCgYIBgAAAA==.',
Er='Eradion:BAAANQADCgYIBwAAAA==.Erisson:BAAANQAECgIIAgAAAA==.',
Es='Eszran:BAAANQADCgYICQAAAA==.',
Fa='Fasani:BAAANQABCgIIAgAAAA==.',
Fe='Fennar:BAAANQAECgEIAQAAAA==.Ferosha:BAAANQAECgIIAgAAAA==.Fexxyr:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.',
Fi='Fiadh:BAAANQABCgQIBAAAAA==.Firm:BAAANQADCgMIBQAAAA==.Firstfear:BAAANQADCgYIBgAAAA==.Fisch:BAAANQADCggIEAAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQADCggIDgAAAA==.Flipingtiska:BAAANQADCgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.',
Fr='Fragmament:BAAANQAECgMIAwAAAA==.Frearyne:BAAANQAECgEIAgAAAA==.Frogs:BAAANQADCgcIBwAAAA==.Frostyshadow:BAAANQAECgQIBwAAAA==.',
Fs='Fstingnemo:BAAANQAECgMIBAAAAA==.',
Fy='Fyxxie:BAAANQAECgcIDAAAAA==.',
Ge='Genvissa:BAAANQAECgQIBAAAAA==.',
Gi='Gialiana:BAAANQAECgEIAQAAAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgYIBgAAAA==.Greenymeany:BAAANQAECgQIBAAAAA==.Grully:BAAANQAECgQIBAAAAA==.',
Ha='Haggard:BAAANQADCgEIAQAAAA==.Hailsbelle:BAAANQADCggIDQAAAA==.Hashtag:BAAANQADCgMIAwAAAA==.',
Hb='Hbic:BAAANQADCgUIBQAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAAANQADCgcIDQAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Ho='Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAAANQADCgUICAAAAA==.',
Ie='Ievil:BAAANQADCgMIBAABNQADCggIDgABAAAAAA==.',
Im='Imjustpika:BAAANQAECgcICwAAAA==.',
In='Inawee:BAAANQAECgQIBQAAAA==.Inferniö:BAAANQAECgcIDQAAAA==.Inkurushio:BAAANQAECgIIAwAAAA==.',
Io='Iolanie:BAAANQADCggICAAAAA==.',
Is='Ismat:BAAANQAECgQIBQAAAA==.',
Ja='Jaeza:BAAANQABCgQIBQABNQAECgEIAQABAAAAAA==.Jarshh:BAAANQADCggIDgAAAA==.',
Jo='Johnefive:BAAANQAECgQIBQAAAA==.Jorrick:BAAANQADCggIDgAAAA==.',
Ka='Kalukaynas:BAAANQADCgEIAQABNQADCgQIBwABAAAAAA==.',
Ke='Kelaan:BAAANQADCggIEAABNQAECgEIAQABAAAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQADCgEIAQAAAA==.',
Ki='Kiritos:BAAANQADCggIDgAAAA==.Kiserys:BAAANQADCgcIBwAAAA==.',
Ko='Kollia:BAAANQADCgEIAgAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAAANQADCgEIAQAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.',
Lo='Lookforlight:BAAANQAECgQIBAAAAA==.Lorenth:BAAANQADCggICgAAAA==.',
Lu='Lucid:BAAANQADCgUICAAAAA==.Luckyjade:BAAANQADCgYIBgAAAA==.',
['Lì']='Lìte:BAAANQADCgYICwAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAAANQAECgIIAgAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Malagu:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.Malidros:BAAANQADCgYICwAAAA==.Marhault:BAAANQAECgQIBQAAAA==.Masitaka:BAAANQAECgMIBQAAAA==.Matt:BAAANQABCgQIBAAAAA==.Maxicat:BAAANQADCgQIBAAAAA==.Maximus:BAAANQADCgYICwAAAA==.Mazah:BAAANQAECgQIBQAAAA==.Mazlo:BAAANQAECgUIBgAAAA==.',
Me='Meleebrain:BAAANQABCgEIAQABNQAECgQIBQABAAAAAA==.Mellethir:BAAANQAECgIIAgAAAA==.Mex:BAAANQADCgUIBQAAAA==.',
Mi='Minipimp:BAAANQABCgQICQAAAA==.Mistbringer:BAAANQADCgQIBgAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAAANQADCgcIDgAAAA==.Moglayn:BAAANQAECgQIBAAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAEANQAECgcICwAAAA==.Mortis:BAAANQADCgIIAgAAAA==.',
My='Myspace:BAAANQADCgYIBgAAAA==.',
['Mø']='Mørbid:BAAANQADCgYIBgAAAA==.',
Na='Nakiki:BAAANQADCgUIBgAAAA==.Nastyiam:BAAANQAECgEIAQAAAA==.',
Ne='Nerfornothin:BAAANQADCgYIBwAAAA==.Nethflap:BAAANQAECgQIBAAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCgEIAQAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAAANQAECgcICQAAAA==.',
No='Norgahl:BAAANQADCgEIAQAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAAANQAECgQIBQAAAA==.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQADCgcIDQAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.',
Ou='Outstanding:BAAANQADCgUIBwABNQADCgYICwABAAAAAA==.',
Pa='Pandoosevelt:BAAANQADCgQIAwAAAA==.',
Pe='Pepis:BAAANQADCggICAAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.',
Pi='Pilgor:BAAANQAECgIIAgAAAA==.',
Po='Polkovnik:BAAANQAECggIDwAAAA==.',
Pr='Pravaat:BAAANQADCgYICgAAAA==.Preroll:BAAANQADCgIIAQAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
['Pæ']='Pæsta:BAAANQAECgMIAQAAAA==.',
Qu='Qubit:BAEANQADCgYICwABNQADCggIDwABAAAAAA==.',
Ra='Rast:BAAANQADCgYICwAAAA==.Rastabout:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Ravel:BAAANQADCggIDgAAAA==.',
Re='Reclaim:BAAANQAECgIIAgAAAA==.Reios:BAAANQADCgEIAQAAAA==.',
Rh='Rhaz:BAAANQADCgcIDQAAAA==.Rhoup:BAAANQADCgcIBgAAAA==.',
Ri='Rickyspanish:BAAANQAECgIIAgAAAA==.Rifter:BAAANQADCgYICgAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.',
Ro='Roupert:BAAANQADCgUICgABNQADCgcIBgABAAAAAA==.',
Ru='Rubyouraw:BAAANQADCgcIDQAAAA==.Ruffneck:BAAANQADCgcIDAAAAA==.Russk:BAAANQADCgIIAgAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICAAAAA==.',
Sa='Saelaan:BAAANQAECgEIAQAAAA==.Sailfu:BAAANQAECgYICgABNQAECgYICQABAAAAAA==.Salami:BAAANQADCgQIBAAAAA==.Samo:BAAANQADCgYICwAAAA==.Sandarr:BAAANQADCgYICgAAAA==.Sanguinne:BAAANQADCgQIBwAAAA==.Santhus:BAAANQADCgcIDAAAAA==.Sargemarge:BAAANQAECgMIBAAAAA==.',
Sc='Sci:BAAANQAECgMIBgAAAA==.',
Se='Selener:BAAANQADCgYICwAAAA==.Serrata:BAAANQADCgMIAwAAAA==.Seymorweiner:BAAANQADCgMIAwAAAA==.',
Sh='Shamski:BAAANQADCgYIBQAAAA==.',
Si='Silther:BAAANQADCggIDwAAAA==.',
Sl='Slavka:BAAANQADCgEIAQAAAA==.',
Sm='Smaalls:BAAANQADCgIIAgAAAA==.Smote:BAAANQADCgYIBgAAAA==.',
Sn='Snâppy:BAAANQADCgYICwAAAA==.',
So='Soloron:BAAANQADCgYIDAAAAA==.Sorrowsöng:BAAANQADCggIDgAAAA==.',
Sp='Sparrhawk:BAAANQADCgcIDAAAAA==.Spiced:BAAANQAECgYIBAAAAA==.',
St='Stabulôus:BAAANQADCgEIAQAAAA==.Starskream:BAAANQABCgQIBAAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stormfall:BAAANQADCgYICwAAAA==.Streea:BAAANQABCgQIBgABNQAECgEIAQABAAAAAA==.',
Sy='Synsairis:BAAANQADCggIDgAAAA==.',
Ta='Talonknight:BAAANQADCgYICwAAAA==.Tavinz:BAAANQADCgYICQAAAA==.',
Th='Thaendofyou:BAAANQADCgMIAwAAAA==.Thalonis:BAAANQABCgIIAgAAAA==.Thelas:BAAANQADCgIIAgAAAA==.Therise:BAAANQADCgQICAABNQAECgQIBQABAAAAAA==.Thetank:BAAANQAECgQIBAAAAA==.Thoroughbred:BAAANQADCgEIAQAAAA==.Throwdini:BAAANQAECgMIAwAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQADCgYIBQABNQAECgQIBQABAAAAAA==.',
Tr='Trotsky:BAAANQAECgIIAwAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAAANQAECgQIBQAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Ty='Tyfa:BAAANQADCgYIBgAAAA==.Tyriem:BAAANQADCggIDwAAAA==.Tyssanton:BAAANQADCgEIAQAAAA==.',
Tz='Tziganin:BAAANQADCggIDgAAAA==.',
Ug='Uggork:BAAANQADCgQIBwAAAA==.',
Un='Unholybussy:BAAANQADCggIDgAAAA==.',
Ut='Utaadh:BAAANQADCggIDQAAAA==.',
Va='Vaelhorn:BAAANQADCgYICwAAAA==.Vallerin:BAAANQADCgQICAAAAA==.',
Ve='Velaar:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Vi='Vicenti:BAAANQADCgYICwAAAA==.',
Vo='Vodnar:BAAANQAECgcIDQAAAA==.',
Vu='Vulnixia:BAAANQADCgEIAQAAAA==.',
Wa='Walls:BAAANQADCgYICwAAAA==.Waste:BAAANQADCggICAAAAA==.Wawel:BAAANQAECgMIBQAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECgMIBgABAAAAAA==.',
Xe='Xerethis:BAAANQADCgcIDAAAAA==.',
Yo='Yogí:BAAANQAECgIIAwAAAA==.Yokos:BAAANQADCgMIAwAAAA==.',
Za='Zahneel:BAAANQADCggICgAAAA==.Zarallia:BAAANQAECgEIAQAAAA==.Zaratul:BAAANQAECgYICgAAAA==.Zarisong:BAAANQADCggICwAAAA==.',
Zh='Zhawaricus:BAAANQADCgUIBAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
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
