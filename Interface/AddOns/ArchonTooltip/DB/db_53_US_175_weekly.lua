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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Unknown-Unknown','Mage-Arcane','DeathKnight-Blood','Rogue-Assassination','Priest-Holy','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Warrior-Arms','Hunter-BeastMastery','Paladin-Retribution','Mage-Frost','Monk-Mistweaver','Warrior-Protection','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','DemonHunter-Devourer','Paladin-Protection',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abiotic:BAAANQADCgQIBQAAAA==.',
Ac='Acaleus:BAAANQAECgQIBAAAAA==.',
Ad='Adric:BAAANQAECgUJCQAAAA==.Aduhgall:BAAANQADCgUICQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAABNQAECoEXAAMBAAgK4CAtEAD6AgABAAgK4CAtEAD6AgACAAEKtRk/ZQBLAAAAAA==.Airbubble:BAAANQABCgEIAQAAAA==.Aiydaen:BAAANQADCgQIAwAAAA==.Aiytan:BAAANQADCgMIAwAAAA==.',
Al='Alarus:BAABNQAECoEeAAIDAAgKyhGzLAAAAgADAAgKyhGzLAAAAgAAAA==.Alex:BAAANQAECgUJDgAAAA==.Alivathor:BAAANQAECgIIAgABNQAECgQJBwAEAAAAAA==.Allypally:BAAANQAECgUICQAAAA==.',
Am='Amgrod:BAEANQADCgUJBQAAAA==.Amway:BAAANQADCgQIBgAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.Andeyn:BAAANQADCgEIAQAAAA==.Angelkitty:BAAANQADCgYIBgAAAA==.',
Ap='Apophiz:BAAANQADCgYIBgAAAA==.',
Ar='Arcadius:BAAANQADCgIIAgAAAA==.Ardur:BAAANQADCgUJBQAAAA==.Aremis:BAAANQAECgEIAQAAAA==.Arkhitype:BAAANQAECgUIBgAAAA==.Aryadel:BAAANQABCgQIBAAAAA==.Aryahi:BAAANQAECggJAQAAAA==.',
As='Ashyslashy:BAAANQAECgYJCAAAAA==.Asur:BAAANQAECgQIBgAAAA==.',
Au='Auracorusca:BAAANQAECgUICwAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.Aynilith:BAAANQAECgQIBwAAAA==.',
Ba='Bajr:BAAANQAECgQIBgAAAA==.Bakura:BAAANQAECgYIDgAAAA==.Banker:BAAANQAECgUICQAAAA==.Baroo:BAAANQADCgcIHwAAAA==.',
Be='Berko:BAABNQAECoErAAIFAAgK4R7GSwCoAgAFAAgK4R7GSwCoAgAAAA==.Beyorne:BAAANQAECgEIAQAAAA==.',
Bh='Bhaang:BAAANQAECgMIBAAAAA==.',
Bi='Bigbear:BAAANQADCgYIBgABNQAECggJFwAGALQkAA==.Bigbill:BAAANQADCgcJCgAAAA==.Bigdeath:BAAANQAECgUJCwAAAA==.Bizco:BAAANQAECgUJDAAAAA==.',
Bj='Bjebo:BAABNQAECoEYAAIDAAgKWA1JMwDPAQADAAgKWA1JMwDPAQAAAA==.',
Bl='Bluffshot:BAAANQAECgYJDAAAAA==.',
Br='Brutes:BAAANQADCggICAABNQAECgkJIwACAJ0kAA==.Brynjalf:BAAANQAECgQJBwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
Bx='Bxck:BAAANQAECgEIAQAAAA==.',
['Bï']='Bïcho:BAAANQAECggIBwAAAA==.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cascadio:BAAANQAECgEIAQAAAA==.Castanza:BAAANQADCgQIBwAAAA==.Caswyn:BAAANQAECgEJAQAAAA==.',
Ch='Charjer:BAAANQAECgUIBgAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.Choney:BAAANQAECgQJBgAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgcIBwAEAAAAAA==.Cojostudio:BAAANQADCggICAAAAA==.Comboost:BAAANQAECgEIAQAAAA==.',
Cr='Cranks:BAAANQADCggICAAAAA==.Crashcake:BAABNQAECoEWAAICAAkKRRwiDQDYAgACAAkKRRwiDQDYAgAAAA==.Creakybones:BAAANQABCgIIAgAAAA==.Croager:BAAANQAECgQJBAAAAA==.',
Cu='Cup:BAAANQAECgUICQAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQAECgMIAwAEAAAAAA==.',
Cy='Cywen:BAAANQADCggJCAABNQAECgkJGwAHAF8fAA==.',
Da='Daelaris:BAAANQAECgYIDgAAAA==.Damonoris:BAAANQAECgYJDQAAAA==.Damthrax:BAAANQAECgQIBQAAAA==.Danielan:BAAANQADCggICAAAAA==.Davegrôwl:BAAANQADCgEJAQABNQADCggIFQAEAAAAAA==.',
De='Deadair:BAAANQADCgMIAwAAAA==.Deadlyalba:BAAANQADCgYIBgAAAA==.Deadzeo:BAAANQADCgYICQAAAA==.Dejavoid:BAAANQADCgIIAgAAAA==.Demonblades:BAAANQAECgYJDAAAAA==.Demonbreaker:BAAANQAECgUIEgAAAA==.Denarten:BAAANQAECgcJEgAAAA==.',
Di='Diotima:BAAANQADCgUICQAAAA==.Dirtymorris:BAAANQAECgcJCgAAAA==.',
Do='Dockevorkian:BAABNQAECoEfAAIIAAgKtSL9EQDvAgAIAAgKtSL9EQDvAgAAAA==.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAAANQAECgcIEAAAAA==.Doublebonus:BAAANQADCggICAABNQAECgkJIwACAJ0kAA==.Dougdk:BAABNQAECoEXAAIGAAgKtCQtCQBCAwAGAAgKtCQtCQBCAwAAAA==.',
Dr='Dracoz:BAAANQADCgEIAQAAAA==.Dricex:BAAANQADCgYIBgAAAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryblood:BAAANQADCgQIBAAAAA==.Dryx:BAAANQAECgIIAgAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
Ea='Eargroan:BAAANQADCgYIBgABNQAECgkJFgAJAMAjAA==.',
El='Elilla:BAAANQAECgUIBgAAAA==.Elkminster:BAAANQADCggIBgAAAA==.Ellenaya:BAAANQAECggICAAAAA==.Elorela:BAAANQADCgQIBAABNQAECgQICAAEAAAAAA==.',
En='Enjoy:BAABNQAECoEjAAMCAAkKnSTHAgCdAwACAAkK4yPHAgCdAwABAAkK7SIpCgBBAwAAAA==.',
Fa='Famiki:BAAANQADCgcICwAAAA==.',
Fe='Felnollid:BAAANQAECgcIEwAAAA==.Fenanigans:BAABNQAECoEbAAIHAAgKWCG6CQDuAgAHAAgKWCG6CQDuAgAAAA==.',
Fi='Firebender:BAAANQADCgQIBAAAAA==.Firetiger:BAAANQADCgcIBwAAAA==.Fistandcider:BAAANQADCgMIAwAAAA==.',
Fl='Fluffyhusky:BAAANQAECgYJDwAAAA==.',
Fo='Fontss:BAAANQAECgUJBgAAAA==.Fonyfish:BAAANQAECgQIBQAAAA==.',
Fu='Fubina:BAEBNQAECoEXAAMKAAkKahjSDgCOAgAKAAkKahjSDgCOAgALAAEKihy6IABNAAAAAA==.',
Fy='Fyjalla:BAAANQADCggJEAAAAA==.',
Ga='Gabh:BAAANQADCgYIBgAAAA==.',
Gi='Gilgaglaive:BAAANQAECgYJDQAAAA==.Gilgämesh:BAABNQAECoEiAAIMAAkKkSFQGAAmAwAMAAkKkSFQGAAmAwAAAA==.',
Gl='Glomah:BAAANQAECgYJDAAAAA==.Glorm:BAAANQAECgYIDQAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.',
Gr='Grabbyhands:BAAANQADCggIFQAAAA==.Grantul:BAAANQAECgUIDAAAAA==.Grimthore:BAAANQADCgUICgABNQAECgQIBgAEAAAAAA==.Grolgan:BAAANQADCgYIBgAAAA==.Gromz:BAAANQAECgIJAgAAAA==.',
Gu='Gulbhang:BAAANQAECgcIEwAAAA==.',
He='Health:BAAANQAECgEIAQAAAA==.',
Ho='Holdi:BAAANQADCgYIBgABNQAECgcIEwAEAAAAAA==.Holyhammer:BAAANQAECgQIBAAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.',
Hu='Hujo:BAAANQAECgYICgAAAA==.Hushpupi:BAAANQAECgQICAAAAA==.Huskerpower:BAAANQADCgcJDQAAAA==.',
Ic='Iceharted:BAAANQADCgEIAQAAAA==.Icesloth:BAAANQAECgUICwAAAA==.',
Id='Idamarie:BAAANQAECgUJBQAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAAANQAECgUICAAAAA==.',
In='Indecisa:BAAANQADCgUIBQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIDAAAAA==.',
Ix='Ixiya:BAAANQADCgQIBwAAAA==.',
Ja='Jaggerss:BAAANQAECgEIAQABNQAECgkJIwACAJ0kAA==.Jamaican:BAAANQADCgYIEAAAAA==.Jaste:BAAANQAECgYJCwAAAA==.',
Ji='Jimit:BAAANQADCgcIBwAAAA==.Jimmym:BAAANQAECgIJAgAAAA==.Jirakaidae:BAAANQADCgYICwABNQAECgEIAQAEAAAAAA==.',
Ju='Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaedeyn:BAAANQADCgEIAQAAAA==.Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgYIBgAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Kh='Khármá:BAAANQAECgQJBwAAAA==.',
Ki='Kicklocks:BAAANQAECgEIAQAAAA==.Kikuri:BAAANQAECgEIAQAAAA==.Killt:BAAANQAECgQIBQAAAA==.',
Ko='Koojoé:BAAANQAECgQIBAAAAA==.',
Ku='Kurzulan:BAAANQAECgUJBwAAAA==.',
La='Laghles:BAABNQAECoEeAAINAAgK5yAJFwDwAgANAAgK5yAJFwDwAgAAAA==.Laroes:BAAANQAECgEIAQABNQAECgYJDAAEAAAAAA==.Larua:BAAANQABCgQJBAAAAA==.Laylriely:BAAANQAECgQIBwAAAA==.',
Le='Lemanjá:BAAANQAECgIJAgAAAA==.',
Li='Lightlooter:BAAANQADCgYIBgAAAA==.Liliane:BAAANQAECgUICAAAAA==.Limbless:BAAANQAECgQIBwAAAA==.',
Lo='Loahealth:BAAANQAECgcIBwAAAA==.Lockrocks:BAAANQAECgcIEQABNQAECgQIBgAEAAAAAA==.Loko:BAAANQADCgcICQAAAA==.Lontra:BAAANQADCgQIBgAAAA==.Loozer:BAAANQAECgQIBgAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAAANQAECgIIAgABNQAECggIEQAEAAAAAA==.Mahlaan:BAABNQAECoEZAAIGAAgKDBmkHgBhAgAGAAgKDBmkHgBhAgAAAA==.Malakai:BAAANQADCgIIAgABNQAECgUJCAAEAAAAAA==.Malekai:BAAANQAECgUJCAAAAA==.Malzen:BAAANQADCgMIAwABNQAECgUJCAAEAAAAAA==.Manaleia:BAAANQADCggIDAAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Mar:BAAANQAECgIIAgAAAA==.Maruug:BAAANQADCgYIBgAAAA==.Marvinah:BAAANQAECgIJAgAAAA==.',
Me='Meatcurtin:BAAANQADCgQIBAAAAA==.Meatlover:BAAANQAECgUJCAAAAA==.Mediocre:BAAANQAECgcJDwAAAA==.Meeshka:BAAANQAECgIIBAAAAA==.Meraleona:BAAANQAECgIIAwAAAA==.Methslinger:BAAANQAECgQJBAAAAA==.',
Mi='Migue:BAAANQABCgEJAgABNQAECgkJJwAOACchAA==.',
Mo='Moarass:BAAANQAECgQJBgABNQAECgYIDAAEAAAAAA==.Moris:BAAANQAECgEIAQAAAA==.Mortmuzi:BAAANQADCgYJBwAAAA==.',
Ms='Mswizzlë:BAAANQAECgUJBQAAAA==.',
Mu='Muldah:BAABNQAECoEXAAMPAAgK5RGDDwA3AQAFAAgKLQ60jAD3AQAPAAcKqQqDDwA3AQAAAA==.',
Na='Nas:BAAANQAECgQJCAAAAA==.Nausicaa:BAAANQABCgYJCQAAAA==.Nausicaä:BAAANQADCgUJBQAAAA==.Navie:BAAANQAECgQICQAAAA==.Nazgûl:BAAANQABCgYIBAAAAA==.',
Ne='Nekros:BAAANQADCgcIBwABNQAECgUIBgAEAAAAAA==.Neø:BAAANQAECgUIDwAAAA==.',
Ni='Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQADCgcIFAAAAA==.Nightshala:BAAANQADCgYJBgAAAA==.',
No='Nokastakaj:BAAANQAECgQJBwAAAA==.Nornyr:BAAANQADCgEIAQAAAA==.',
Nu='Nunsrsus:BAAANQAECgcIDwAAAA==.',
Ny='Nymerias:BAAANQADCgYJDgAAAA==.Nyrrah:BAAANQAECgMIBAAAAA==.',
['Ná']='Nácht:BAAANQAECgIIAgAAAA==.',
['Ný']='Nýghtmyst:BAAANQAECgEJAQAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Om='Omaticaya:BAAANQAECgUJDgAAAA==.Omèn:BAAANQADCgUIBQAAAA==.',
Op='Optikon:BAAANQAECgUIDAAAAA==.',
Or='Oriax:BAAANQADCggJEQAAAA==.',
Ow='Owlbearcat:BAAANQAECgYJCAABNQAECgcIBwAEAAAAAA==.',
Oz='Ozempic:BAAANQADCgYICAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgYJDgAAAA==.Paj:BAAANQAECgYJDgAAAA==.',
Pk='Pkalygos:BAAANQAECgUICAAAAA==.',
Pl='Pleione:BAAANQAECgUJBwAAAA==.',
Po='Powerstrokee:BAAANQADCggIEwAAAA==.',
Pr='Preyforme:BAAANQAECgQJCgAAAA==.Prusik:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.',
Ps='Psychelone:BAAANQADCggIDgAAAA==.',
Qu='Quillan:BAAANQADCgUJCQABNQAECgcIDwAEAAAAAA==.',
Qy='Qyxh:BAAANQAECgUJDAAAAA==.',
Ra='Raine:BAAANQADCgUICAAAAA==.Rastafarian:BAAANQADCgUICQAAAA==.',
Re='Rehne:BAAANQAECgEJAQAAAA==.Rexhavoc:BAAANQAECgcJDgAAAA==.Rexion:BAAANQADCgYIEgAAAA==.',
Ri='Ripre:BAAANQADCgUIBgAAAA==.',
Ro='Rosary:BAAANQAECgQIBwAAAA==.Rosewoodren:BAAANQADCgcICwAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAAANQAECgUIBwAAAA==.',
['Rï']='Rïvkah:BAAANQADCgUIBgABNQAECgQIBAAEAAAAAA==.',
Sa='Saauurrora:BAAANQADCgYIBgAAAA==.Saintshift:BAAANQADCgEJAQABNQAECgMIAwAEAAAAAA==.Salitheion:BAAANQADCggICwAAAA==.Sapper:BAABNQAECoEaAAIQAAgKah7aBwDFAgAQAAgKah7aBwDFAgAAAA==.Sarn:BAAANQADCggICAAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Se='Sennest:BAAANQADCgUIAwAAAA==.',
Sh='Shikí:BAAANQAECgEIAQAAAA==.Shladoran:BAAANQAECgMJBAAAAA==.Shos:BAABNQAECoEWAAIRAAgKuhuJBgCFAgARAAgKuhuJBgCFAgAAAA==.',
Si='Sinnister:BAAANQADCgYIBgAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQAECggJFwAGALQkAA==.',
Sn='Snapdragyn:BAAANQADCggIBgAAAA==.Snorina:BAABNQAECoEZAAISAAcKGB3YFQBEAgASAAcKGB3YFQBEAgAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Sosgoraan:BAAANQADCgcJBwAAAA==.Sosozen:BAAANQAECgUJBwAAAA==.',
Sp='Spirittoast:BAAANQADCgYJDAAAAA==.',
Sr='Sriman:BAAANQAECgYIBgAAAA==.',
St='Starkiller:BAAANQADCgYIDgAAAA==.Stonesolid:BAAANQAECgUJDgAAAA==.',
Su='Supremacy:BAABNQAECoETAAMTAAgKiiQHEgD+AgATAAcKZCUHEgD+AgAUAAEKmB4zVgBYAAAAAA==.',
Sw='Sweetspot:BAAANQAECgQIBQABNQAECgQIBgAEAAAAAA==.Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAAANQAECgUICQAAAA==.',
Sy='Sylrytherin:BAAANQADCgYICgABNQAECgcIGQASABgdAA==.Sylvii:BAABNQAECoEaAAIVAAgKnhLXFwD1AQAVAAgKnhLXFwD1AQAAAA==.',
Ta='Tabor:BAAANQADCggICwAAAA==.Taggz:BAAANQABCgQIBAAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAAANQAECgUIDgAAAA==.Tauryel:BAAANQAECgEIAQABNQAECgQIBwAEAAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.Tethlis:BAAANQADCggICAABNQAECgcJFwAGADgaAA==.',
Th='Thasarias:BAAANQAECgIIAgAAAA==.Themoosifer:BAACNQAFFIEJAAIWAAUKORR2AwCyAQAWAAUKORR2AwCyAQA1AAQKgR4AAhYACQpPICQKABEDABYACQpPICQKABEDAAAA.Thyck:BAAANQAECgUICgAAAA==.Thydis:BAABNQAECoEYAAIOAAcK2woDgwB2AQAOAAcK2woDgwB2AQAAAA==.',
Ti='Tiancit:BAAANQADCgEIAQAAAA==.Tibbs:BAAANQAECgYJDAAAAA==.Ticklepickle:BAAANQAECgIIBAAAAA==.',
To='Tooch:BAAANQADCggICAAAAA==.',
Tr='Trumalice:BAAANQADCgQICgAAAA==.',
Tu='Tulpa:BAAANQABCgQJCgAAAA==.',
Un='Uncorrupted:BAABNQAECoEdAAMXAAkK6BKOEwDjAQAXAAgK+BSOEwDjAQAOAAIKigSUHwE1AAAAAA==.',
Up='Updog:BAAANQAECgEIAQABNQAECgIIBAAEAAAAAA==.',
Va='Vaelm:BAAANQADCgIIAwAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAAANQAECgUICQAAAA==.',
Ve='Velathila:BAAANQADCgUIEwAAAA==.',
Vi='Violêt:BAAANQADCgYIBgAAAA==.Vizzelok:BAAANQAECgQIBAAAAA==.',
Vo='Voidchris:BAAANQAECgYJEQAAAA==.Voidormu:BAAANQADCgcIGgAAAA==.',
Wa='Warelf:BAAANQAECggJEwAAAA==.Warleck:BAAANQAECgEIAQAAAA==.',
Wh='Whodey:BAAANQAECgQJBAABNQAECgUJCAAEAAAAAA==.',
Wi='Wisp:BAAANQADCgUIBQAAAA==.',
Wy='Wylia:BAAANQAECgQIBAAAAA==.',
Xc='Xcw:BAAANQAECgIIAgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAAANQAECgcIEgAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgABNQAECgMIAwAEAAAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zuldave:BAAANQAECgQJCgAAAA==.',
Zy='Zylera:BAAANQADCggICwAAAA==.Zyphor:BAAANQADCggICAAAAA==.Zyth:BAAANQABCgMIAgAAAA==.',
['Ñî']='Ñîx:BAAANQAECgUJDAAAAA==.',
['Ød']='Ødinson:BAAANQAECgEJAQAAAA==.',
['ßæ']='ßær:BAAANQAECgIJAgAAAA==.',
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
