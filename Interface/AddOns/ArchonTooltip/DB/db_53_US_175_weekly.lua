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

local lookup = {'Unknown-Unknown','Mage-Arcane','DeathKnight-Unholy','Rogue-Assassination','DeathKnight-Frost','Warrior-Arms','Paladin-Retribution','DemonHunter-Devourer','Paladin-Protection',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECgQIBAAAAA==.Aduhgall:BAAANQADCgUICQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAAANQAECgYIDQAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAAANQAECgUIEwAAAA==.Alex:BAAANQAECgUIDgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Allypally:BAAANQAECgIIAgAAAA==.',
Am='Amgrod:BAEANQADCgUIBQAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Ardur:BAAANQADCgUIBQAAAA==.Aremis:BAAANQADCgcIBwAAAA==.Arkhitype:BAAANQAECgEIAQAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECgIIAQAAAA==.',
As='Ashyslashy:BAAANQAECgUIBwAAAA==.Asur:BAAANQAECgIIAgAAAA==.',
Au='Auracorusca:BAAANQAECgQIBwAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAAANQAECgMIAwAAAA==.',
Ba='Bajr:BAAANQAECgQIBgAAAA==.Bakura:BAAANQAECgQICQAAAA==.Banker:BAAANQAECgMIBAAAAA==.Baroo:BAAANQADCgcIGQAAAA==.',
Be='Berko:BAABNQAECoEoAAICAAgJ4R6qMwDDAgACAAgJ4R6qMwDDAgAAAA==.Beyorne:BAAANQADCggICAAAAA==.',
Bh='Bhaang:BAAANQAECgEIAQAAAA==.',
Bi='Bigbear:BAAANQADCgYIBgABNQAECgcIEwABAAAAAA==.Bigbill:BAAANQADCgMIAwAAAA==.Bigdeath:BAAANQAECgQIBgAAAA==.Bizco:BAAANQAECgUIBwAAAA==.',
Bj='Bjebo:BAAANQAECgYIDgAAAA==.',
Bl='Bluffshot:BAAANQAECgQIBgAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAECgkJHQADAI0jAA==.Brynjalf:BAAANQAECgMIAwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
Bx='Bxck:BAAANQABCgIIAgAAAA==.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cascadio:BAAANQADCgUIDQAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAAANQADCgMIAwAAAA==.',
Ch='Charjer:BAAANQAECgEIAQAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgQIBAAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgYIBgABAAAAAA==.Cojostudio:BAAANQADCggICAAAAA==.Comboost:BAAANQAECgEIAQAAAA==.',
Cr='Crashcake:BAAANQAECgcIDQAAAA==.Croager:BAAANQAECgQIBAAAAA==.',
Cu='Cup:BAAANQAECgMIBAAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
Cy='Cywen:BAAANQADCggICAABNQAECgkJGQAEAPodAA==.',
Da='Daelaris:BAAANQAECgUICQAAAA==.Damonoris:BAAANQAECgUIBwAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQADCggICAAAAA==.',
De='Deadair:BAAANQADCgMIAwAAAA==.Deadlyalba:BAAANQADCgYIBgAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Dejavoid:BAAANQADCgIIAgAAAA==.Demonblades:BAAANQAECgQIBgAAAA==.Demonbreaker:BAAANQAECgUICAAAAA==.Denarten:BAAANQAECgYICwAAAA==.',
Di='Diotima:BAAANQADCgUICQAAAA==.Dirtymorris:BAAANQAECgcICgAAAA==.',
Do='Dockevorkian:BAAANQAECgcIEwAAAA==.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAAANQAECgYIDQAAAA==.Doublebonus:BAAANQADCggICAABNQAECgkJHQADAI0jAA==.Dougdk:BAAANQAECgcIEwAAAA==.',
Dr='Dracoz:BAAANQADCgEIAQAAAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQADCgYICwAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.',
El='Elilla:BAAANQAECgEIAQAAAA==.Elkminster:BAAANQADCgcIBgAAAA==.Ellenaya:BAAANQAECgcIBwAAAA==.Elorela:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.',
En='Enjoy:BAABNQAECoEdAAMDAAkJjSPABgBiAwADAAkJ7SLABgBiAwAFAAgJOyH7BgABAwAAAA==.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Felnollid:BAAANQAECgcIDAAAAA==.Fenanigans:BAAANQAECgcIEAAAAA==.',
Fi='Firebender:BAAANQADCgQIBAAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCgMIAwAAAA==.',
Fl='Fluffyhusky:BAAANQAECgYIDgAAAA==.',
Fo='Fontss:BAAANQADCgYIBgAAAA==.Fonyfish:BAAANQADCggIEgAAAA==.',
Fu='Fubina:BAEANQAECgcIDgAAAA==.',
Fy='Fyjalla:BAAANQADCggIEAAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.',
Gi='Gilgaglaive:BAAANQAECgYICgAAAA==.Gilgämesh:BAABNQAECoEeAAIGAAkJjiAFFAAnAwAGAAkJjiAFFAAnAwAAAA==.',
Gl='Glomah:BAAANQAECgQIBgAAAA==.Glorm:BAAANQAECgUIDAAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.',
Gr='Grabbyhands:BAAANQADCggIDgAAAA==.Grantul:BAAANQAECgQIBwAAAA==.Grimthore:BAAANQABCgQIBAABNQAECgQIBgABAAAAAA==.Grolgan:BAAANQADCgYIBgAAAA==.',
Gu='Gulbhang:BAAANQAECgUIDQAAAA==.',
He='Health:BAAANQAECgEIAQAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Holyhammer:BAAANQAECgQIBAAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.',
Hu='Hujo:BAAANQAECgUICgAAAA==.Hushpupi:BAAANQAECgQICAAAAA==.Huskerpower:BAAANQADCgYIDAAAAA==.',
Ic='Iceharted:BAAANQADCgEIAQAAAA==.Icesloth:BAAANQAECgQIBwAAAA==.',
Id='Idamarie:BAAANQADCggIEQAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAAANQAECgMIAwAAAA==.',
In='Indecisa:BAAANQADCgUIBQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIDAAAAA==.',
Ix='Ixiya:BAAANQADCgQIBwAAAA==.',
Ja='Jaggerss:BAAANQAECgEIAQABNQAECgkJHQADAI0jAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAAANQAECgIIBQAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAAANQADCgYICQAAAA==.Jirakaidae:BAAANQADCgYICwABNQADCgcIBwABAAAAAA==.',
Ju='Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Kh='Khármá:BAAANQAECgIIAwAAAA==.',
Ki='Kicklocks:BAAANQAECgEIAQAAAA==.Killt:BAAANQAECgMIBAAAAA==.',
Ko='Koojoé:BAAANQAECgQIBAAAAA==.',
Ku='Kurzulan:BAAANQAECgMIBQAAAA==.',
La='Laghles:BAAANQAECgcIEwAAAA==.Laroes:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Laylriely:BAAANQAECgMIAwAAAA==.',
Le='Lemanjá:BAAANQAECgIIAgAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAAANQAECgMIAwAAAA==.Limbless:BAAANQAECgQIBQAAAA==.',
Lo='Lockrocks:BAAANQAECgQICgABNQAECgQIBgABAAAAAA==.Lontra:BAAANQADCgQIBgAAAA==.Loozer:BAAANQAECgQIBgAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAAANQADCgQIBAAAAA==.Mahlaan:BAAANQAECgYIDwAAAA==.Malakai:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.Malekai:BAAANQAECgQIBwAAAA==.Malzen:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQADCgUIDgAAAA==.',
Me='Meatcurtin:BAAANQADCgQIBAAAAA==.Meatlover:BAAANQAECgQIBQAAAA==.Mediocre:BAAANQAECgYICgAAAA==.Meeshka:BAAANQAECgEIAgAAAA==.Meraleona:BAAANQAECgIIAwAAAA==.Methslinger:BAAANQAECgQIBAAAAA==.',
Mi='Migue:BAAANQABCgEIAgABNQAECggIGgAHAG0hAA==.',
Mo='Moarass:BAAANQAECgQIBgABNQAECgYIBgABAAAAAA==.Moris:BAAANQADCgcIDwAAAA==.Mortmuzi:BAAANQADCgYIBwAAAA==.',
Mu='Muldah:BAAANQAECgcIDQAAAA==.',
Na='Nas:BAAANQAECgMIBAAAAA==.Nausicaä:BAAANQADCgUIBQAAAA==.Navie:BAAANQAECgQICQAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Neø:BAAANQAECgUICgAAAA==.',
Ni='Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQADCgcIFAAAAA==.',
No='Nokastakaj:BAAANQAECgIIAwAAAA==.Nornyr:BAAANQADCgEIAQAAAA==.',
Nu='Nunsrsus:BAAANQAECgYIDgAAAA==.',
Ny='Nymerias:BAAANQADCgYIDgAAAA==.Nyrrah:BAAANQAECgMIAwAAAA==.',
['Ná']='Nácht:BAAANQAECgIIAgAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEIAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Om='Omaticaya:BAAANQAECgUICQAAAA==.Omèn:BAAANQADCgUIBQAAAA==.',
Op='Optikon:BAAANQAECgUIDAAAAA==.',
Or='Oriax:BAAANQADCggIEQAAAA==.',
Ow='Owlbearcat:BAAANQAECgYIBgAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgQICwAAAA==.Paj:BAAANQAECgQIBgAAAA==.',
Pk='Pkalygos:BAAANQAECgMIAwAAAA==.',
Pl='Pleione:BAAANQAECgEIAQAAAA==.',
Po='Powerstrokee:BAAANQADCggIEQAAAA==.',
Pr='Preyforme:BAAANQAECgQIBgAAAA==.Prusik:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ps='Psychelone:BAAANQADCggIDgAAAA==.',
Qu='Quillan:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.',
Qy='Qyxh:BAAANQAECgQIBwAAAA==.',
Ra='Raine:BAAANQADCgUICAAAAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Rehne:BAAANQAECgEIAQAAAA==.Rexhavoc:BAAANQAECgQIBwAAAA==.Rexion:BAAANQADCgYIDAAAAA==.',
Ri='Ripre:BAAANQADCgUIBgAAAA==.',
Ro='Rosary:BAAANQAECgIIAwAAAA==.Rosewoodren:BAAANQADCgcICwAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAAANQAECgEIAgAAAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBgABNQAECgQIBAABAAAAAA==.',
Sa='Saintshift:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Salitheion:BAAANQADCgcICwAAAA==.Sapper:BAAANQAECgcIDwAAAA==.Sarn:BAAANQADCggICAAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shladoran:BAAANQAECgEIAQAAAA==.Shos:BAAANQAECgcIDgAAAA==.',
Si='Sinnister:BAAANQADCgYIBgAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAECgcIEwABAAAAAA==.',
Sn='Snapdragyn:BAAANQADCgcIBgAAAA==.Snorina:BAAANQAECgYIDgAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcIBwAAAA==.Sosozen:BAAANQAECgIIAgAAAA==.',
Sp='Spirittoast:BAAANQADCgQICQAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAAANQAECgUICQAAAA==.',
Su='Supremacy:BAAANQAECgYIDQAAAA==.',
Sw='Sweetspot:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAAANQAECgMIBAAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECgYIDgABAAAAAA==.Sylvii:BAAANQAECgYIEAAAAA==.',
Ta='Tabor:BAAANQADCgcICwAAAA==.Taggz:BAAANQABCgQIBAAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAAANQAECgQIBQAAAA==.Tauryel:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAAAAA==.',
Th='Thasarias:BAAANQADCggIDAAAAA==.Themoosifer:BAABNQAECoEbAAIIAAkJBCDKBwAnAwAIAAkJBCDKBwAnAwAAAA==.Thyck:BAAANQAECgUICgAAAA==.Thydis:BAAANQAECgUIDgAAAA==.',
Ti='Tiancit:BAAANQADCgEIAQAAAA==.Tibbs:BAAANQAECgQIBgAAAA==.Ticklepickle:BAAANQAECgIIAgABNQADCggICAABAAAAAA==.',
To='Tooch:BAAANQADCggICAAAAA==.',
Tr='Trumalice:BAAANQADCgQICgAAAA==.',
Tu='Tulpa:BAAANQABCgQICgAAAA==.',
Un='Uncorrupted:BAABNQAECoEWAAMJAAkJjBFwEQCxAQAJAAcJQxVwEQCxAQAHAAIJigS+5gA3AAAAAA==.',
Up='Updog:BAAANQADCggICAAAAA==.',
Va='Vaelm:BAAANQADCgIIAwAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAAANQAECgMIBAAAAA==.',
Ve='Velathila:BAAANQADCgUIDAAAAA==.',
Vi='Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAAANQADCggIDwAAAA==.',
Vo='Voidchris:BAAANQAECgQICgAAAA==.Voidormu:BAAANQADCgcIEwAAAA==.',
Wa='Warelf:BAAANQAECggICwAAAA==.Warleck:BAAANQAECgEIAQAAAA==.',
Wi='Wisp:BAAANQADCgUIBQAAAA==.',
Wy='Wylia:BAAANQAECgQIBAAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAAANQAECgUICwAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zuldave:BAAANQAECgQIBgAAAA==.',
Zy='Zylera:BAAANQADCgcICwAAAA==.Zyphor:BAAANQADCggICAAAAA==.Zyth:BAAANQABCgMIAgAAAA==.',
['Ñî']='Ñîx:BAAANQAECgQIBwAAAA==.',
['Ød']='Ødinson:BAAANQAECgEIAQAAAA==.',
['ßæ']='ßær:BAAANQADCggICwAAAA==.',
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
