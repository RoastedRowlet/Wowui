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

local lookup = {'Druid-Restoration','Unknown-Unknown','Paladin-Holy','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Vengeance','Druid-Balance',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acbabcaa:BAAANQADCgEIAQAAAA==.Aceon:BAAANQAECgEIAQAAAA==.Aceonarcher:BAAANQAECgMIAwAAAA==.',
Ad='Adfectia:BAAANQAECgEIAQAAAA==.',
Ae='Aelianna:BAAANQADCgcICwAAAA==.Aeth:BAAANQAECgQIBQAAAA==.Aethér:BAAANQAECgQIBAABNQAECgkJFgABAJ4iAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgIIAgAAAA==.',
Al='Alexstrászá:BAAANQAECgIIAgAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgMIBAAAAA==.',
Am='Amewow:BAAANQAECggIEgAAAA==.',
An='Anarchy:BAAANQADCgcIDgAAAA==.Andraxi:BAAANQADCgUIBQAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Anorakswrath:BAAANQAECgIIAgAAAA==.',
Ap='Apophys:BAAANQADCgUIBgAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Aruneza:BAAANQAECgEIAQAAAA==.',
As='Ashèr:BAAANQADCggIFQAAAA==.Asunnaa:BAAANQADCgEIAgAAAA==.',
At='Atenchion:BAAANQADCgMIAgAAAA==.',
Au='Aura:BAAANQAECgQIBAAAAA==.Autoignition:BAAANQAECgUIBwAAAA==.',
Ba='Bahnkano:BAAANQAECgIIAgAAAA==.Bakeddh:BAAANQADCgYIDAAAAA==.Banditz:BAAANQADCgQIBgAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAAANQAECgEIAQAAAA==.Beenah:BAAANQADCgYIEAAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgEIAQAAAA==.',
Bo='Bombmagic:BAAANQADCgMIAwAAAA==.Boomie:BAAANQAECggIBQAAAA==.Boopty:BAAANQAECgEIAQAAAA==.Booptydo:BAAANQADCgIIAgAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAAANQADCgcICwAAAA==.',
Bp='Bpwhunter:BAAANQAECgQIBgAAAA==.',
Br='Braiin:BAAANQADCgcIBwABNQAECgkJFgABAJ4iAA==.Brazyn:BAAANQADCgYICwAAAA==.Brevarda:BAAANQAECgEIAgAAAA==.',
Bu='Bubblzmgee:BAAANQAECgQICQAAAA==.Buscemi:BAAANQADCgYIBgAAAA==.Bustofez:BAAANQADCgUIBQAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQADCgIIAgAAAA==.',
Ca='Caracalous:BAAANQAECgUIBQAAAA==.Carindria:BAAANQABCgIIBAAAAA==.Carninn:BAAANQADCgUIBQAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cattiebrie:BAAANQAECgEIBAAAAA==.Caylavana:BAAANQAECgQIBgAAAA==.',
Ce='Celaylria:BAAANQAECgQIBAAAAA==.',
Ch='Chantille:BAAANQADCgYIDAAAAA==.Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgQICQAAAA==.Clugorn:BAAANQAECgMIBAAAAA==.Clydè:BAAANQADCgYICQAAAA==.',
Co='Colourhunt:BAAANQAECgQIBAAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAAANQAECgEIAQAAAA==.Corrode:BAAANQADCggIEAAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cy='Cybeldin:BAAANQADCggIDwAAAA==.Cyberdemonxd:BAAANQADCgQIBQABNQADCgYIBgACAAAAAA==.Cyndyr:BAAANQADCgUICwAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAAANQADCgYIEQAAAA==.Darek:BAAANQADCgUIBQAAAA==.Darilyns:BAAANQADCgEIAQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgUIBgAAAA==.Darylinn:BAAANQADCgQIBAAAAA==.',
De='Dernis:BAAANQAECgIIAgABNQAECgMIAwACAAAAAA==.Deshaman:BAAANQADCgMIAwABNQAECgcIDgACAAAAAA==.Devilbeast:BAAANQAECgMIAwAAAA==.',
Dh='Dhargo:BAAANQADCgcIBwAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Disgruntled:BAAANQAECgQIBAAAAA==.',
Do='Dontormentaa:BAAANQAECgIIAgABNQAECgUIBwACAAAAAA==.Dontormentaj:BAAANQAECgUIBwAAAA==.Doomzday:BAAANQADCgYIBwAAAA==.',
Dr='Dracthra:BAAANQAECgEIAQAAAA==.Drakk:BAAANQADCgUIBQABNQABCgMIAwACAAAAAA==.Dreamlesnite:BAAANQABCgUIBgAAAA==.Dreidelman:BAAANQAECgEIAQAAAA==.',
Du='Dugdimadome:BAAANQADCgUIBQAAAA==.',
Dy='Dylora:BAAANQAECgEIAQAAAA==.',
Ea='Ealdoras:BAAANQADCgYIBgAAAA==.',
Eg='Egg:BAABNQAECoEWAAIDAAkJbB5dAwBoAwADAAkJbB5dAwBoAwABNQAFFAYIBgAEABkLAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAAANQAECgQIBgAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQADCggIDwAAAA==.Elystaria:BAAANQADCgYIDQAAAA==.',
Em='Emokins:BAEANQAECgEIAQAAAA==.',
Ep='Epicnakedman:BAAANQAECggICAAAAA==.',
Er='Erubus:BAAANQAECgYIDAAAAA==.Eryss:BAAANQADCgYIFAAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAAANQADCgYICwAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAAANQAECgEIAQAAAA==.',
Fe='Fellariene:BAAANQADCgUIBQAAAA==.',
Fo='Forilla:BAAANQAECgMIAwAAAA==.Fortissimo:BAAANQADCgIIAgAAAA==.',
['Fà']='Fàmous:BAAANQAECgEIAQAAAA==.',
Ga='Galabris:BAAANQADCgYIDAAAAA==.Gasilbench:BAAANQADCgQIBAAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQADCgQIBwAAAA==.Gitchusum:BAAANQADCgMIAwAAAA==.',
Gl='Glaivenez:BAAANQAECgEIAQAAAA==.Gleenna:BAAANQADCgUIBQAAAA==.',
Go='Goose:BAAANQAECgIIAgAAAA==.Gormladin:BAAANQADCgQIBwAAAA==.Gormstorm:BAAANQADCgYIDQAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grouchy:BAAANQADCgQIBgABNQAECgEIAQACAAAAAA==.',
Ha='Halfang:BAAANQADCgUICgAAAA==.',
Hi='Hitpoints:BAAANQADCgUIBwABNQAECgEIAQACAAAAAA==.',
Ho='Holyhope:BAAANQAECgIIAgABNQAECggICAACAAAAAA==.Holymana:BAAANQAECgMIBAAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.',
Ht='Htet:BAAANQAECgQICAAAAA==.',
Hu='Huffingpaint:BAAANQADCgMIAwABNQADCgYIDAACAAAAAA==.Hukhokhan:BAAANQADCggICAAAAA==.Hutzil:BAAANQAECgQICAAAAA==.',
Ia='Iakopa:BAAANQAECgUICwABNQAECgcIEAACAAAAAA==.',
Il='Illidianna:BAAANQAECgEIAQAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.Imitlol:BAAANQAECgcIBwAAAA==.',
It='Itchynyple:BAAANQADCgUIBgAAAA==.',
Ja='Jacques:BAAANQADCgUIBQAAAA==.Jaetherion:BAAANQADCggIEgAAAA==.Jakes:BAAANQADCgUIBQAAAA==.Jayhawk:BAAANQAECgEIAQAAAA==.',
Ji='Jimothy:BAAANQADCgcIDQABNQADCggICAACAAAAAA==.Jinx:BAAANQADCgYIDQAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQADCggICwAAAA==.Jonesy:BAAANQADCgIIAgABNQAECgYICwACAAAAAA==.',
['Jà']='Jàccuse:BAAANQADCgQIBQABNQAECgEIAQACAAAAAA==.Jàrnsaxa:BAAANQADCgYIDgAAAA==.',
['Jò']='Jòhnnypopo:BAAANQAECgEIAQAAAA==.',
Ka='Kasumeli:BAAANQAECgYIBQAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayhan:BAAANQADCgMIAwAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQADCgUICwAAAA==.Kazurend:BAABNQAECoEWAAIFAAkJjB4cBABOAwAFAAkJjB4cBABOAwAAAA==.',
Ke='Keyaielenst:BAAANQADCgUIBQAAAA==.',
Kh='Khirina:BAAANQADCgcIDAAAAA==.Khristina:BAAANQAECgEIAQAAAA==.Khrogh:BAAANQADCgYICwAAAA==.',
Ki='Kippo:BAEANQAECgcICAAAAA==.',
Kn='Knarn:BAAANQAECgEIAQAAAA==.',
Ko='Koralie:BAABNQAECoEYAAIGAAkJciQtAQC5AwAGAAkJciQtAQC5AwAAAA==.Korrum:BAAANQABCgMIAgAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgAAAA==.',
Ky='Kyliekat:BAAANQAECgEIAQAAAA==.',
La='Lanel:BAAANQAECgIIAwAAAA==.Lathelous:BAAANQAECgEIAQAAAA==.',
Le='Leintheir:BAAANQADCgIIAgAAAA==.',
Li='Lightt:BAAANQAECgYIDQAAAA==.Liightt:BAAANQAECgIIAgAAAA==.Lilcozz:BAAANQADCgUICwAAAA==.Lilpyroblast:BAAANQAECgQIBQAAAA==.Liriope:BAAANQADCgUIBQAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUIBQAAAA==.Llars:BAAANQAECgEIAQAAAA==.',
Lo='Loryanna:BAAANQADCgYICgAAAA==.Louie:BAAANQADCgYIDQAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgIIAgAAAA==.',
Ly='Lyandrea:BAAANQADCgUIBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAAANQAECgEIAQAAAA==.',
Ma='Main:BAAANQAECgUIBwAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAAANQADCgcIDQAAAA==.Malicemech:BAAANQADCgYIEQAAAA==.Maliceone:BAAANQADCgYIDQAAAA==.Malicepaly:BAAANQADCgEIAQAAAA==.Mallucavian:BAAANQADCgYICQAAAA==.Mamadp:BAAANQAECgIIAgAAAA==.Manek:BAAANQAECgYICwAAAA==.Marraxa:BAAANQADCggIDwAAAA==.Max:BAAANQAECgUIBQAAAA==.',
Me='Melinoe:BAAANQADCgIIAgAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgIIAgAAAA==.Mishosuki:BAAANQADCgYIBwAAAA==.Misscleo:BAAANQAECgEIAQAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Mobmagnet:BAABNQAECoEaAAIHAAkJeRiOAQCZAgAHAAkJeRiOAQCZAgAAAA==.Moltres:BAEANQAECggIBQABNQAFFAQIAgACAAAAAA==.Moonkist:BAAANQADCgYICQAAAA==.Moose:BAAANQAECgUIBgAAAA==.Mordrandian:BAAANQADCgUICwAAAA==.Morroe:BAAANQADCgYIDAAAAA==.',
Mu='Muffintop:BAAANQADCgQIBAAAAA==.',
Na='Nadless:BAAANQADCgYIDAAAAA==.Naeliria:BAAANQADCggICAAAAA==.Naki:BAAANQADCgUICQAAAA==.Namuss:BAAANQADCgEIAQAAAA==.Navariis:BAAANQADCgQICgAAAA==.',
Ne='Nelrehim:BAAANQADCgYICgAAAA==.',
Ni='Niandilan:BAAANQADCgUIBgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQADCgEIAgABNQAECgEIAQACAAAAAA==.',
No='Noirheffer:BAAANQAFFAEIAQAAAA==.Nokua:BAAANQADCgYIDwABNQADCgYIEAACAAAAAA==.Noodles:BAAANQADCgEIAQAAAA==.',
Nu='Nulannatoo:BAAANQAECgEIAQAAAA==.',
Ny='Nyank:BAAANQADCgYIBgAAAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyxaraa:BAAANQADCgYIBgAAAA==.',
Oc='Octomore:BAAANQAECgEIAQAAAA==.',
Od='Odysseus:BAAANQAECgYICgAAAA==.',
Ol='Olguita:BAAANQADCgIIAgAAAA==.',
Om='Omgowned:BAAANQADCgYIDAABNQAECgEIAQACAAAAAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Op='Opheliastar:BAAANQAECgYICwAAAA==.',
Or='Ordovis:BAAANQAECgQIBAAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAAANQADCgYIDwAAAA==.Paladerp:BAAANQADCggIEwAAAA==.Palanym:BAAANQADCggIFgAAAA==.Palidyne:BAAANQAECgEIAQAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.',
Ph='Phelement:BAAANQAECgIIAwAAAA==.Phett:BAAANQAECgQIBAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.Pimmscup:BAAANQADCgUIBgAAAA==.',
Qo='Qohelet:BAAANQAECgMIAwAAAA==.',
Ra='Raenya:BAAANQAECgEIAQAAAA==.Rainydaze:BAAANQADCgYICgAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.Ramoreo:BAAANQAECgQIBAABNQADCgcIDQACAAAAAA==.Rashun:BAAANQADCggIFAAAAA==.Raviolee:BAAANQADCgUICgABNQAECgEIAQACAAAAAA==.',
Re='Reanatilax:BAAANQABCgMIBQABNQAECgEIAQACAAAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQADCgcICwABNQAECgIIAwACAAAAAA==.',
Ri='Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Ropebunnyana:BAAANQAECgIIAwAAAA==.',
Ru='Ruki:BAAANQADCgYIDAAAAA==.',
Sa='Saltydk:BAAANQAECgYICwAAAA==.Samiracy:BAAANQAECgEIAQAAAA==.',
Sc='Scappe:BAAANQAECgYICgAAAA==.',
Se='Senbatorii:BAAANQAECgEIAQAAAA==.Sethrow:BAAANQAECgEIAQAAAA==.Severa:BAAANQAECgIIAgAAAA==.',
Sh='Shadoh:BAAANQADCgYIBgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowza:BAAANQADCgcIGgAAAA==.Shantifa:BAAANQADCgUIBQAAAA==.Shoshanaa:BAAANQADCgIIAgAAAA==.Shotcallà:BAAANQADCgYIBgAAAA==.Shuna:BAAANQADCgMIAwAAAA==.Shyly:BAAANQADCggIGwAAAA==.',
Si='Siley:BAAANQAECgQIDgAAAA==.',
Sn='Sneakysneak:BAAANQADCgcIBwAAAA==.',
So='Somepriest:BAAANQAECgEIAQAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Spycmchaggis:BAAANQADCgYICwAAAA==.',
St='Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sunow:BAAANQADCgMIAwAAAA==.Superdemonzz:BAAANQAECgEIAQABNQAECgcIEwACAAAAAA==.Superpallyz:BAAANQAECgcIEwAAAA==.Superspidey:BAAANQADCgIIAgAAAA==.',
Sw='Swipeleft:BAAANQAECgYICgAAAA==.',
Sy='Sylveslem:BAAANQABCgIIAgAAAA==.',
Ta='Tabarnak:BAAANQADCgYIBgABNQAECggIDwACAAAAAA==.Tarogen:BAAANQADCgYICgAAAA==.',
Te='Tendroni:BAAANQADCgcIBwAAAA==.Tervor:BAAANQADCgUICgAAAA==.',
Th='Thanamoros:BAAANQAECgUIAwABNQAECgcIEAACAAAAAA==.Theroach:BAAANQADCggICAAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.',
Ti='Timeismoney:BAAANQABCgMIAwAAAA==.Tiognaska:BAAANQADCgcICAAAAA==.',
Tl='Tlcbm:BAAANQAECgYIBgAAAA==.',
To='Toeren:BAAANQAECgcIDgAAAA==.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgEIAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgUIBwACAAAAAA==.',
Tr='Trenity:BAAANQAECgEIAQAAAA==.Triplecanopy:BAAANQADCgUICwAAAA==.',
Ty='Tyinorin:BAAANQADCgUICwAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAAANQADCggIEgAAAA==.',
Ug='Uglyelf:BAAANQADCggIEgAAAA==.',
Ul='Ultimakitty:BAAANQADCggICAAAAA==.',
Un='Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vantrix:BAAANQAECgcIEAAAAA==.Varabo:BAAANQADCgcIBgAAAA==.Varolina:BAAANQADCgIIAwAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAAANQADCgcIDAAAAA==.Velyra:BAAANQADCgYIDQAAAA==.',
Vi='Vivieneaux:BAAANQABCgMIBAAAAA==.',
Vo='Vosaleana:BAAANQADCgQIDQAAAA==.',
Vr='Vraak:BAABNQAECoEWAAMBAAkJniL9AACJAwABAAkJniL9AACJAwAIAAEJVBzZUwBGAAAAAA==.',
Vy='Vyndarien:BAAANQABCgUIBwAAAA==.',
Wa='Wa:BAAANQADCgYIEgAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wi='Will:BAAANQAECgcIDwAAAA==.',
Wo='Womdalie:BAAANQADCgUIDgAAAA==.',
Wy='Wyckedpally:BAAANQADCgYIEAAAAA==.',
Xa='Xanthös:BAAANQAECgEIAQABNQAECgkJFgABAJ4iAA==.',
Xe='Xemnastrasza:BAAANQAECgYIBgABNQAECgcIEAACAAAAAA==.Xenonne:BAAANQAECgMIBAAAAA==.',
Xo='Xolither:BAAANQAECgEIAQAAAA==.',
Yo='Yourwivesbf:BAAANQADCggICQAAAA==.',
Za='Zachdemon:BAAANQAECgQIBgAAAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zenyátta:BAAANQADCgcIEgAAAA==.Zephymoo:BAAANQAECgYIDAAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zeyana:BAAANQAECgYICAABNQAECgcIEAACAAAAAA==.',
Zh='Zhengshi:BAAANQAECgEIAQAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgIIAgAAAA==.',
Zo='Zoose:BAAANQAECgEIAQAAAA==.Zoser:BAAANQADCggIEgAAAA==.',
Zu='Zuckuss:BAAANQADCgUICwAAAA==.',
Zy='Zymri:BAAANQADCgQIBAABNQADCgYIEAACAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Öl']='Ölivê:BAAANQADCggIDQAAAA==.',
['ßu']='ßugs:BAAANQADCggIFgAAAA==.',
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
