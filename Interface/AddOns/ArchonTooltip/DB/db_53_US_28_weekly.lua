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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abednego:BAAANQAECgUICQAAAA==.',
Ac='Acidrain:BAAANQAECgIIAgAAAA==.Acmiax:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ad='Adonsinn:BAAANQADCgcIEAAAAA==.',
Ae='Aegos:BAAANQADCggIEAAAAA==.Aep:BAAANQAECgEIAQABNQADCgUIBwABAAAAAA==.',
Ah='Ahu:BAABNQAECoEXAAMCAAkJJhPdFAB/AgACAAkJJhPdFAB/AgADAAEJKga3PQA0AAAAAA==.',
Al='Alakazam:BAAANQADCgUIBgAAAA==.Alanath:BAAANQADCgQIBAAAAA==.Allaria:BAAANQAECgEIAQAAAA==.Alucard:BAAANQADCggICAAAAA==.',
Am='Amaging:BAAANQAECgQIBAAAAA==.Amoondai:BAAANQAFFAEIAQAAAA==.',
Ap='Apochryphal:BAAANQAECgIIAgAAAA==.',
As='Ashogg:BAAANQADCgYIBgAAAA==.',
Au='Aurén:BAAANQADCgQIBAAAAA==.',
Az='Azuree:BAAANQAECgEIAQAAAA==.',
Ba='Bacstabath:BAAANQAECgcIDwAAAA==.',
Be='Becca:BAAANQAECgQIBwAAAA==.',
Bi='Bigduh:BAAANQADCgQIBAAAAA==.Birblock:BAAANQAECgQIBAABNQAECggIEgABAAAAAA==.',
Bl='Blaizee:BAAANQADCgIIAgAAAA==.Bloodios:BAAANQAECgQIBAAAAA==.Bluechewgold:BAAANQAECgYICwAAAA==.',
Bo='Bobbardment:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Bobin:BAAANQAECgEIAgAAAA==.Bombadil:BAAANQAECgIIAgAAAA==.Boshek:BAAANQABCgMIBQAAAA==.',
Br='Bribage:BAAANQAECggIEgAAAA==.Brightest:BAAANQAECgIIAQAAAA==.Brolaf:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.Brolavski:BAAANQAECgUIBQAAAA==.',
Bu='Budderwar:BAAANQAECgQIBgAAAA==.Buster:BAAANQAECgEIAQAAAA==.',
['Bà']='Bàdmofos:BAAANQADCgQIBAAAAA==.',
Ce='Celerydk:BAAANQAECgQIBwAAAA==.',
Co='Colossus:BAAANQAECgEIAgAAAA==.Connor:BAAANQAECgIIBAAAAA==.Correin:BAAANQAECgMIAwAAAA==.',
Cr='Craszhin:BAAANQAECgIIAgAAAA==.Crime:BAAANQAECgEIAgAAAA==.',
['Cè']='Cèl:BAAANQAECgQIBAAAAA==.',
Da='Daddio:BAEANQAECgQIBAAAAA==.Dangpup:BAAANQAECgYICAAAAA==.Danru:BAAANQADCgQICwAAAA==.Darkdelight:BAAANQAECgYICwAAAA==.',
De='Deathlylazy:BAAANQADCgYICwAAAA==.Deets:BAAANQAECgIIAgAAAA==.Demona:BAAANQAECgIIAgAAAA==.Descalabrada:BAAANQADCggICAAAAA==.',
Di='Distol:BAAANQADCgIIAgAAAA==.',
Dr='Driver:BAAANQAECgYIAwAAAA==.Drpeppers:BAAANQADCggIFgAAAA==.',
['Dé']='Déathsavage:BAAANQADCgUIBwAAAA==.',
Ec='Eclair:BAAANQAECgIIAgAAAA==.',
El='Elfkr:BAAANQAECgMIBQAAAA==.Elhayn:BAAANQADCggIDgAAAA==.Elmos:BAAANQAECgYICwAAAA==.',
Er='Erethidian:BAAANQADCgQIBAAAAA==.',
Ev='Evilmonkeymg:BAEANQAECgYICAAAAA==.Evilmonkeysh:BAEANQADCgUIBQABNQAECgYICAABAAAAAA==.',
Ez='Ezaylia:BAAANQAECgIIAgAAAA==.',
Fa='Fatehunter:BAAANQADCgcIEAAAAA==.',
Fe='Feim:BAAANQADCggICAAAAA==.Fergis:BAAANQAECgIIAgAAAA==.',
Fi='Firefox:BAAANQAECgUIBgAAAA==.',
Fl='Flypig:BAAANQADCggIBwAAAA==.',
Fr='Frostymonk:BAAANQADCgcIEAAAAA==.Frostypally:BAAANQABCgEIAQAAAA==.',
Fu='Furrybear:BAAANQADCgYICwAAAA==.',
Gi='Gigem:BAAANQAECgMIAwAAAA==.Girlshoon:BAAANQADCggICgAAAA==.Githan:BAAANQAECgYICgAAAA==.',
Gl='Glarious:BAAANQAECgcICQAAAA==.',
Gr='Gredan:BAAANQADCgcIEQAAAA==.Greymoor:BAAANQABCgQIBAAAAA==.Gruhm:BAAANQADCgUIBQAAAA==.Grôg:BAAANQADCggICAAAAA==.',
Gu='Guldaniel:BAAANQAECgEIAQAAAA==.Guthuzad:BAAANQADCgUIBQAAAA==.Guthx:BAAANQAECgEIAgAAAA==.',
He='Hellen:BAAANQAECgEIAgAAAA==.',
Ho='Hotburrito:BAAANQABCgIIAgAAAA==.',
Hw='Hwat:BAAANQADCggICAAAAA==.',
Ic='Ictus:BAAANQAECgEIAgAAAA==.',
In='Incredabull:BAAANQADCgcIDgAAAA==.',
Is='Isabelle:BAAANQADCgIIAgAAAA==.Isharded:BAAANQAECgQIBAAAAA==.Istayblunted:BAAANQADCgcIDQAAAA==.',
Ja='Jaylon:BAAANQADCgUIBQAAAA==.',
Ji='Jiayerah:BAAANQADCgQIBAABNQADCgcIEQABAAAAAA==.Jinkuzo:BAAANQADCggIDgAAAA==.Jinmu:BAAANQAECgIIAgAAAA==.',
Ju='Juanaloopa:BAAANQADCgIIAQAAAA==.Juggie:BAAANQAECgEIAQAAAA==.Julienned:BAAANQAECgQIBAAAAA==.',
['Jè']='Jèsse:BAAANQADCgQIBAAAAA==.',
Ka='Kainen:BAAANQAECgIIAgAAAA==.',
Kl='Klum:BAAANQABCgQIBgAAAA==.',
La='Lanfear:BAAANQADCgQIBAAAAA==.',
Le='Leinen:BAAANQADCgYIBwAAAA==.',
Lo='Logi:BAAANQADCgUIBwAAAA==.',
Lu='Lumiyer:BAAANQADCggICQABNQAECgkJFwAEALohAA==.',
Ly='Lygor:BAAANQADCggIFQAAAA==.Lykana:BAAANQADCggIEgAAAA==.',
Ma='Magnifico:BAAANQADCgYIBwAAAA==.Majellan:BAAANQAECgQIBAAAAA==.Marsawn:BAAANQAECgQIBAAAAA==.Mass:BAABNQAECoEYAAIFAAkJ/yNcAAC7AwAFAAkJ/yNcAAC7AwABNQAFFAYICwAGAM4PAA==.',
Me='Meatbatticus:BAAANQAECgEIAgAAAA==.Meqi:BAAANQADCgcIEQAAAA==.',
Mi='Mindlessness:BAAANQAECgIIAgAAAA==.Mineralelf:BAAANQAECgQIBAAAAA==.Minichaos:BAAANQADCggIEgAAAA==.Miriam:BAAANQAECgUICQAAAA==.',
Mo='Mojosavage:BAAANQAECgEIAQAAAA==.Moonblade:BAAANQABCgYIDAAAAA==.',
My='Mysticalfox:BAAANQADCgEIAQAAAA==.',
Na='Nalfilas:BAAANQADCgYICQAAAA==.',
Ne='Nephaleos:BAAANQAECgQIBgAAAA==.Nessie:BAAANQADCgYIBgAAAA==.',
Ni='Nihlus:BAAANQADCgQIBQAAAA==.',
Ny='Nyrvana:BAAANQAECgIIAgAAAA==.',
['Nà']='Nàtureswrath:BAAANQADCgcIDAAAAA==.',
Or='Orceo:BAAANQAECgYICAAAAA==.Orkreghar:BAAANQAECgQIBQAAAA==.',
Pa='Pallon:BAAANQAECgUIBQAAAA==.',
Ph='Phazma:BAAANQADCgUIBQAAAA==.',
Pi='Pindapin:BAAANQAECgEIAQAAAA==.',
Po='Pompompower:BAAANQAECgUICgAAAA==.Popashammy:BAAANQAECgEIAQAAAA==.Popple:BAAANQADCggIFAAAAA==.Potential:BAAANQAECgQIBAAAAA==.',
Qu='Quixotical:BAAANQADCgYIBgAAAA==.',
Ra='Radaghast:BAAANQADCggIDAAAAA==.',
Re='Reishirome:BAAANQADCgUIBQAAAA==.Revenmar:BAAANQADCgQIBAAAAA==.',
Rh='Rhaelin:BAAANQAECgEIAQAAAA==.Rhoke:BAAANQAECgUIBwAAAA==.',
Ro='Romeoz:BAAANQADCgMIAwAAAA==.Rona:BAAANQAECgQIBwAAAA==.Rosary:BAAANQAECgEIAgAAAA==.Rotiserychic:BAAANQADCgUIBQAAAA==.',
Ru='Rusticfinger:BAAANQAECgEIAQAAAA==.',
Sa='Sacerdote:BAAANQAECgEIAQAAAA==.Sansa:BAAANQADCgcIEQAAAA==.Saruma:BAAANQADCggIBAABNQADCggICAABAAAAAA==.',
Sc='Scalygrob:BAAANQAECgEIAgAAAA==.Scarytery:BAAANQAECgQIBgAAAA==.Scrügemcmonk:BAAANQAECgQIBAAAAA==.',
Sh='Shamfox:BAAANQADCgcIEAAAAA==.',
Sm='Smogcheck:BAAANQAECgcICwAAAA==.',
Sn='Snowsz:BAAANQADCgcIBwAAAA==.Snowws:BAAANQAECgQIBAAAAA==.',
So='Sonektot:BAAANQAECgEIAQAAAA==.Sortis:BAAANQAECgYICwAAAA==.',
Sp='Spicebreff:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
St='Steck:BAAANQADCgYIEAAAAA==.Strigg:BAAANQADCgMIAwABNQADCggIEQABAAAAAA==.Strigöi:BAAANQADCggIEQAAAA==.',
Su='Suprahunts:BAAANQAECgQIBAAAAA==.',
Ta='Talander:BAAANQADCgUIBQAAAA==.Talas:BAAANQAECgYICwAAAA==.',
Th='Thaeker:BAAANQADCggIDgAAAA==.Thrann:BAAANQAECgMIAwAAAA==.',
Ti='Tirium:BAAANQAECgQIBAAAAA==.',
To='Tolkien:BAAANQADCgcIDQAAAA==.',
Tu='Tubbytotem:BAAANQADCgYICgAAAA==.',
Ur='Ursae:BAAANQADCgIIAgAAAA==.',
Va='Vanargandr:BAAANQADCgYIBgAAAA==.Vartlek:BAAANQADCgUIBQAAAA==.',
Ve='Velinlock:BAAANQABCgEIAQAAAA==.',
Vy='Vyxenn:BAAANQAECgQIBAAAAA==.',
Wa='Wanders:BAAANQAECgQIAQABNQAECgQIBAABAAAAAA==.Washim:BAAANQADCgEIAQAAAA==.',
Za='Zaleras:BAAANQADCggIDgAAAA==.',
Ze='Zerkium:BAAANQADCggIFwAAAA==.',
Zi='Zillaamiri:BAAANQAECgIIAgAAAA==.',
Zu='Zugzugdaboo:BAAANQADCggICwAAAA==.',
Zy='Zywol:BAAANQAECgQIBAAAAA==.',
['Ër']='Ëresta:BAAANQADCgYIEgABNQAECgIIAgABAAAAAA==.',
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
