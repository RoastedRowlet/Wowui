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
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-09-01',data={Ae='Aerouant:BAAANQAECgQIBAAAAA==.',
Ai='Aidix:BAAANQADCgQIBgAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAAANQAECgIIAgAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.',
An='Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAAANQAECgIIAgAAAA==.Anthross:BAAANQADCgcIDgAAAA==.',
Ap='Apollovon:BAAANQAECgMIAwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanenug:BAAANQADCgQIBAAAAA==.Armiggy:BAAANQAECgIIAgAAAA==.Aro:BAAANQAECgcIDAAAAA==.Arrowraen:BAAANQAECgIIAgAAAA==.',
As='Asd:BAAANQADCgQIBAAAAA==.',
Au='Audomere:BAAANQADCggIDQAAAA==.Auurwarr:BAAANQADCgIIAgAAAA==.',
Av='Avawrath:BAAANQAECgEIAQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.',
Ba='Bailey:BAAANQADCgIIAgAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQADCgEIAQAAAA==.',
Be='Bearboi:BAAANQAECgMIAwABNQABCgEIAQABAAAAAA==.Bearbomblolz:BAAANQADCgMIBAABNQADCgYICgABAAAAAA==.Bearmanakin:BAAANQADCgYIBgAAAA==.Beastmandes:BAAANQADCgYIBgAAAA==.Bejeezus:BAAANQAECgIIAgAAAA==.Bewslee:BAAANQADCgMIAwAAAA==.Bexx:BAAANQADCgUIBwAAAA==.',
Bi='Biblehumping:BAAANQAECgQIBQAAAA==.Bietk:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQADCgYIBgAAAA==.Blãezer:BAAANQADCgYIBQAAAA==.',
Br='Brewtoe:BAAANQADCgcIDAAAAA==.',
Ca='Cannabinoide:BAAANQADCgMIAwAAAA==.Cannatonic:BAAANQADCgcIDAAAAA==.Catnips:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Ce='Celirra:BAAANQAECgIIAgAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Cheekybaby:BAAANQADCgcIDgAAAA==.Cherrypoplol:BAAANQADCgEIAQAAAA==.Chocopaati:BAAANQADCggICgAAAA==.Chokma:BAAANQADCgYIDAAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chìefponbury:BAAANQADCgYIBgAAAA==.',
Ci='Cinnaa:BAAANQAECgQIBAAAAA==.',
Cl='Clawwz:BAAANQAECgEIAQAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.',
Co='Conflux:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIBAAAAA==.',
Cy='Cyberfairy:BAAANQADCgQIBAAAAA==.Cyphinx:BAAANQAECgEIAQAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgEIAQAAAA==.Dalìnar:BAAANQADCgYICwAAAA==.Damadafacker:BAAANQAECgEIAQAAAA==.Darkclôud:BAAANQADCgYIDAAAAA==.Darklia:BAAANQADCgcIDAAAAA==.Darthjae:BAAANQAECgQICwAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAAANQAECgEIAQAAAA==.Daïn:BAAANQAECgIIBAAAAA==.',
De='Deathalimon:BAAANQAECgQIBQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAAANQADCgcIDAAAAA==.Deroc:BAAANQADCgcIBwAAAA==.Destuk:BAAANQADCgYICgAAAA==.',
Di='Dinfarmer:BAAANQADCgEIAQAAAA==.Dirtycheese:BAAANQAECgQIBAAAAA==.',
Do='Dogfärts:BAAANQADCgMIBAAAAA==.Dorunter:BAAANQADCgcIBwAAAA==.',
Dr='Dragonforge:BAAANQADCgYICwAAAA==.Drakujin:BAAANQADCgMIAwAAAA==.Drdoitall:BAAANQADCgIIAgAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Drstorm:BAAANQADCgYIBgAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.',
En='Enhydra:BAAANQADCgEIAQAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAAANQAECgUICAAAAA==.',
Er='Ericolson:BAAANQADCgEIAQAAAA==.Erze:BAAANQADCgUIBQAAAA==.Erôman:BAAANQADCgIIAgAAAA==.',
Ev='Evé:BAAANQADCggIEAAAAA==.',
Fa='Favabean:BAAANQADCgUIBQABNQAECgQICwABAAAAAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Fengshui:BAAANQADCgYICwAAAA==.Fennil:BAAANQADCgUIBQAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAAANQAECgIIAgAAAA==.Flyhawk:BAAANQADCgIIAgAAAA==.',
Fu='Funkadelfic:BAAANQAECgEIAQAAAA==.',
Ga='Galadri:BAAANQAECgYIBwAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgIIAgAAAA==.Geartryx:BAAANQADCgUIBQAAAA==.',
Gh='Ghoshshadow:BAAANQADCgEIAQAAAA==.',
Gi='Gimpripper:BAAANQADCggIDQAAAA==.Giztron:BAAANQADCgYICAAAAA==.',
Gl='Globalcold:BAAANQAECgMIBQAAAA==.Globb:BAAANQAECgYIDAAAAA==.Globius:BAAANQAECgIIAgAAAA==.Gloriouscole:BAAANQAECgMIAwAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Gr='Greekorc:BAAANQABCgIIAwAAAA==.Grimby:BAAANQADCggIBgAAAA==.Gromol:BAAANQADCggICAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQADCgEIAQAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQADCgMIAwAAAA==.Hatebrêêd:BAAANQADCgEIAQAAAA==.',
He='Healman:BAAANQADCgMIAwAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Herenorthere:BAAANQAECgMIBQABNQAECgUIBgABAAAAAA==.Hermippe:BAAANQADCgYIBgAAAA==.Hexstraits:BAAANQAECgYICQAAAA==.',
Hi='Hia:BAAANQAFFAEIAQAAAA==.',
Ho='Hondaimpala:BAAANQADCgYIBgABNQAECgQICwABAAAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huhdean:BAAANQAECgIIAgAAAA==.Hulxamus:BAAANQADCggICgAAAA==.',
['Hé']='Héåthcliff:BAAANQAECgYICgAAAA==.',
Ic='Icyblaze:BAAANQADCggIEAAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgQIBAABAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQADCgUIBgAAAA==.',
It='Itheusvalles:BAAANQADCggIDQAAAA==.Itsjerry:BAAANQADCgYIBgAAAA==.',
Iw='Iwillcrushyo:BAAANQADCggIDgAAAA==.',
Ja='Jainalynn:BAAANQADCgQICAAAAA==.Jazira:BAAANQADCgYIDQAAAA==.',
Jd='Jdarkside:BAAANQADCgYICwAAAA==.',
Je='Jeremmiah:BAAANQADCgYICQAAAA==.',
Jh='Jhacobo:BAAANQADCgcIDQAAAA==.',
Jr='Jragon:BAAANQAECgIIAgAAAA==.',
Ju='Juicy:BAAANQAECgQIBQAAAA==.Junipur:BAAANQADCgQIBgAAAA==.',
Jx='Jxxy:BAAANQAECgYICQAAAA==.',
['Jú']='Júnjúnwälä:BAAANQADCggICAAAAA==.',
Ka='Kandance:BAAANQADCgQIBAAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ki='Kimbopable:BAAANQADCgUICgABNQAECgQICwABAAAAAA==.Kittyÿ:BAAANQADCgcIBgAAAA==.',
Kr='Krystall:BAAANQADCgIIAgAAAA==.',
Ku='Kuarahy:BAAANQAECgEIAQAAAA==.Kunfugrip:BAAANQADCgQIBAABNQADCggIEAABAAAAAA==.',
La='Lanthos:BAAANQAECgUIBgAAAA==.Larthal:BAAANQADCggIEAAAAA==.Latinpapi:BAAANQAECgEIAQAAAA==.',
Le='Leemiez:BAAANQADCgUIBQAAAA==.',
Li='Lilina:BAAANQAECgQIBAAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Loza:BAAANQADCgQIBAABNQADCggIDQABAAAAAA==.',
Lu='Lucith:BAAANQAECgIIAgAAAA==.Lulafairy:BAAANQADCgYICQAAAA==.Lunawa:BAAANQAECgcIDAAAAA==.',
Ly='Lynnai:BAAANQADCgYIBgAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAAANQAECgYIBgAAAA==.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lô']='Lôuku:BAAANQAECgIIAgAAAA==.',
Ma='Maahn:BAAANQADCgUIBQAAAA==.Macalob:BAAANQADCgMIAwAAAA==.Madallar:BAAANQADCgYICgAAAA==.Magdagni:BAAANQADCgYICwAAAA==.Mageji:BAAANQAECgYICwABNQADCgYIBgABAAAAAA==.Magepies:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Mallgoth:BAAANQAECgQICQAAAA==.Manohar:BAAANQAECgQIBgAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgMIAwAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Metaloclypse:BAAANQADCgIIAgAAAA==.Mezaryn:BAAANQADCgYICgABNQADCgEIAQABAAAAAA==.Mezzoo:BAAANQADCgEIAQAAAA==.',
Mi='Millic:BAAANQADCggIDgAAAA==.Minax:BAAANQAECgEIAQAAAA==.',
Mo='Moozx:BAAANQADCgIIAgAAAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAECgMIAwAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAAANQADCgcIDgAAAA==.Nasuadia:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
Ne='Nekkash:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQADCgcIDAAAAA==.Nuvostaph:BAAANQADCgYICgAAAA==.',
Od='Odecias:BAAANQADCgUIBQAAAA==.',
Og='Ogbrew:BAAANQADCgYIBgAAAA==.',
Or='Orezn:BAAANQAECgIIAgAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Papiace:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.Pato:BAAANQAECgQIBwAAAA==.',
Ph='Phatnips:BAAANQAECgIIAgAAAA==.',
Pi='Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAAANQAECgYICQAAAA==.',
Po='Popedragon:BAAANQADCgYIDAAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Pres:BAAANQADCgIIAgAAAA==.Pryome:BAAANQADCgUIBgABNQAECgQIBQABAAAAAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQADCgUIBwAAAA==.Punkz:BAAANQADCgYICAABNQAECgYIBwABAAAAAA==.Pushmaa:BAAANQADCggICgAAAA==.',
Py='Pytorch:BAAANQAECgQICQAAAA==.',
Qu='Quigzz:BAAANQAECgIIAwAAAA==.Quinnie:BAAANQADCgQIBAAAAA==.',
Ra='Raganarok:BAAANQADCgYICQAAAA==.Rahja:BAAANQADCgYIBgAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQADCgYIBgAAAA==.',
Ri='Ritsu:BAAANQADCgUIBAAAAA==.',
Ro='Rosabetsy:BAAANQADCgIIAgAAAA==.',
['Rô']='Rôbert:BAAANQADCgQIBwAAAA==.',
Sa='Saberyn:BAAANQADCgYIAwAAAA==.Saenya:BAAANQAECgQIBQAAAA==.Sassynova:BAAANQADCgQIBwAAAA==.',
Sc='Scopeftis:BAAANQAECgQIBAAAAA==.',
Se='Seberology:BAAANQAECgcIDgAAAA==.Segagamecube:BAAANQADCgIIAgAAAA==.Sephi:BAAANQADCgQIBAAAAA==.',
Sh='Shaco:BAAANQADCgEIAQAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamownage:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Shepling:BAAANQADCggICAAAAA==.Shivàh:BAAANQAECgcIDAAAAA==.Shneezleberg:BAAANQAECgQIBAAAAA==.',
Si='Sildormi:BAAANQADCgMIAwAAAA==.Sizzlinghots:BAAANQADCgYIBgAAAA==.',
Sk='Sko:BAAANQADCgYIDAAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Snowyrain:BAAANQADCgIIAgAAAA==.',
So='Solkar:BAAANQADCgYICgAAAA==.Solo:BAAANQAECgIIAgAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
St='Stankytotems:BAAANQADCgYICgAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.',
Su='Sunarii:BAAANQADCgYIBgAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.',
['Sà']='Sàviorself:BAAANQADCgYICQAAAA==.',
Ta='Talanath:BAAANQADCgcICQAAAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tazoo:BAAANQADCgYICwAAAA==.',
Te='Teamfluffer:BAAANQADCgMIBAAAAA==.Tee:BAAANQADCgMIAwAAAA==.',
Th='Thabeast:BAAANQADCgUIBQAAAA==.Thadeouss:BAAANQADCggIEAAAAA==.Thebigboom:BAAANQAECgQIBQAAAA==.Thecarter:BAAANQADCgQIBAAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.',
Ti='Tigerchimon:BAAANQADCgUIBQAAAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQADCgYIBgAAAA==.Toxicsocks:BAAANQADCgMIAwAAAA==.',
Tr='Trapscallion:BAAANQADCgcIBwAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAAANQAECgIIAgAAAA==.Treelimbs:BAAANQADCgYIBgAAAA==.Tridity:BAAANQADCgUIBQAAAA==.Trollolollz:BAAANQADCgIIAQAAAA==.',
Ts='Tsuuna:BAAANQAECgQIBQAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.',
['Tê']='Tênaciousv:BAAANQADCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgEIAQAAAA==.',
Un='Ungodlyy:BAAANQADCgUIBwAAAA==.Untöuchable:BAAANQAECgEIAQAAAA==.',
Ur='Urskrog:BAAANQADCggIDAAAAA==.',
Ve='Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAAANQAECgMIAwAAAA==.Verxl:BAAANQAECgEIAQAAAA==.',
Vo='Voidnyou:BAAANQADCgQICAAAAA==.Volumes:BAAANQADCggIDwAAAA==.Volund:BAAANQAECgIIAwAAAA==.',
Vy='Vynsong:BAAANQADCggICgAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Wa='Warwalkerz:BAAANQADCgYIBgAAAA==.',
We='Weemies:BAAANQAECgEIAQAAAA==.',
Wh='Whoyerdaddy:BAAANQADCgEIAQAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winnototem:BAAANQAECgIIAgAAAA==.Wisakedjak:BAAANQADCggIDAAAAA==.Wix:BAAANQADCgcIBwAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCgYIBgAAAA==.',
Xu='Xugos:BAAANQADCggIDgAAAA==.',
Yo='Yochill:BAAANQADCgUIBQABNQADCgYIBQABAAAAAA==.Yooper:BAAANQADCgYIBgAAAA==.',
Yr='Yrgg:BAAANQADCgUIBQAAAA==.',
Za='Zadanthra:BAAANQADCgYICgAAAA==.Zapadin:BAAANQADCgQIBAAAAA==.Zaphodè:BAAANQADCgYIBgAAAA==.',
Ze='Zephsham:BAAANQADCgYIBgAAAA==.',
Zi='Zimone:BAAANQADCgIIAgAAAA==.',
Zo='Zoerik:BAAANQAECgIIAgAAAA==.Zotoperen:BAAANQAECgIIAgAAAA==.',
Zy='Zylergy:BAAANQADCggICgAAAA==.',
['Än']='Ändo:BAAANQAECgEIAQAAAA==.',
['Çy']='Çyrin:BAAANQAECgEIAQAAAA==.',
['Ëu']='Ëuphoria:BAAANQADCgQIBAAAAA==.',
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
