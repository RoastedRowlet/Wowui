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
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Adder:BAAANQADCgIIAgAAAA==.Adrua:BAAANQADCgUIBgAAAA==.Adym:BAAANQAECgIIAgAAAA==.',
Ag='Agave:BAAANQAECgEIAQAAAA==.',
Ai='Aiyah:BAAANQADCgYICQAAAA==.',
Al='Altarboi:BAAANQADCgYICwAAAA==.Alüçard:BAAANQADCgYICgAAAA==.',
Am='Amoraniel:BAAANQAECgMIAwAAAA==.',
An='Andrar:BAAANQADCgYIBwAAAA==.Andres:BAAANQADCgQIBAAAAA==.Andresra:BAAANQAECgUICAAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAAANQAECgEIAgAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.',
Av='Avâtre:BAAANQADCgYIBgAAAA==.',
Ba='Baguette:BAAANQAECgIIAgAAAA==.Bajingobomb:BAAANQAECgEIAQAAAA==.Bakblood:BAAANQABCgQIBAAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.',
Be='Be:BAAANQAECgEIAQAAAA==.Beckyoncé:BAAANQAECgEIAQAAAA==.Bedris:BAAANQADCgcIDQAAAA==.Beerticus:BAAANQAECgEIAQAAAA==.',
Bi='Bigdingus:BAAANQAECgIIAgAAAA==.Binggles:BAAANQAFFAIIAwAAAA==.',
Bl='Blacksheep:BAAANQADCgIIAgAAAA==.',
Bo='Bomboclaat:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.Boolay:BAAANQADCggICAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQADCgQIBAAAAA==.Bosmina:BAAANQAECgQIBQAAAA==.',
Br='Braei:BAAANQADCgYIDAAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Brenmonk:BAAANQADCggIDgAAAA==.',
Bu='Bubblebaddie:BAAANQADCggICgAAAA==.Bugenhagen:BAAANQAECgQIBQAAAA==.Butchers:BAAANQADCgUIBQAAAA==.Buttpaladin:BAAANQADCgYIBgAAAA==.',
Ca='Cardib:BAAANQAECggIDgAAAA==.Cavos:BAAANQAECgMIAwAAAA==.',
Ce='Cernsarn:BAAANQAECgEIAQAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Chiri:BAEANQAECgQIBgAAAA==.Chvngus:BAAANQAECgEIAQAAAA==.',
Ci='Citizencain:BAAANQADCgYIBgAAAA==.',
Cl='Claytnbigsby:BAAANQADCgcIDAAAAA==.',
Co='Coohwhip:BAAANQADCgQIBAAAAA==.',
Cr='Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAAANQADCgcIDAAAAA==.Cristobal:BAAANQADCggIBwAAAA==.',
Da='Dagidan:BAAANQAECgQIBQAAAA==.',
De='Demontotems:BAAANQADCgYIBgAAAA==.Demotoxi:BAAANQADCgMIAwAAAA==.Deriso:BAAANQADCggIBwAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCgQIBQABAAAAAA==.Destrozinth:BAAANQADCgcIBwAAAA==.Dethorok:BAAANQAECgIIAgAAAA==.Deåth:BAAANQADCgEIAQABNQADCgMIBAABAAAAAA==.',
Di='Diagonpally:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Digey:BAAANQAECgEIAQAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAAANQAECgEIAQAAAA==.',
Do='Dopeaf:BAAANQADCgMIBQAAAA==.Dottër:BAAANQADCgMIBAAAAA==.',
Dr='Drakbek:BAAANQADCgYICgAAAA==.Dreadshot:BAAANQADCgYIBgAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dronebot:BAAANQAECgMIBQAAAA==.Drucifer:BAAANQADCggIDwAAAA==.',
Du='Durros:BAAANQADCggIDgAAAA==.',
Em='Embody:BAAANQADCgcIDQAAAA==.',
En='Endlyss:BAAANQADCggIBwAAAA==.',
Er='Erasmas:BAAANQAECgEIAQAAAA==.Erzascarlét:BAAANQAECgQIBQAAAA==.',
Eu='Euphoricx:BAAANQAECgQIBQAAAA==.',
Ev='Evildeader:BAAANQADCggICQAAAA==.Eviltotems:BAAANQADCgcICgABNQADCggICQABAAAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAAANQAECgQIBQAAAA==.Fantasma:BAAANQADCgYICAAAAA==.',
Fi='Findal:BAAANQADCgYIBgAAAA==.Fistymoo:BAEANQADCgIIAgABNQAECgQIBgABAAAAAA==.Fivemagics:BAAANQADCggIBwAAAA==.',
Fl='Fleaboy:BAAANQADCgYICgAAAA==.Flist:BAAANQADCggICAAAAA==.Floof:BAAANQADCgQIBAAAAA==.',
Fo='Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAAANQADCgcIDQAAAA==.',
Fx='Fxce:BAAANQADCgQIBwAAAA==.',
Gh='Ghulz:BAAANQAECgQIBwAAAA==.',
Gi='Gibsmedats:BAAANQAECgEIAQAAAA==.',
Gl='Glaiven:BAAANQAECgIIAgAAAA==.Glasscleaner:BAAANQAECgMIBAABNQAECgcICwABAAAAAA==.Glenmorangie:BAAANQADCgcIDQAAAA==.',
Gn='Gnartusk:BAAANQADCgYIDAAAAA==.',
Gr='Greens:BAAANQADCgYICAAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Grillvy:BAAANQADCgIIAgAAAA==.Grïma:BAAANQAECgQIBQAAAA==.',
Gu='Gueritestje:BAAANQAECgIIAgAAAA==.Guzzlord:BAAANQAECgIIAgAAAA==.',
Ha='Halfman:BAAANQAECgEIAQAAAA==.',
Hb='Hboozing:BAAANQAECgMIAwAAAA==.',
He='Heayt:BAAANQABCgIIBAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Hipdrop:BAAANQADCggIDgAAAA==.Hitoshura:BAAANQAECgEIAQAAAA==.',
Ho='Holyginger:BAAANQADCgcICgAAAA==.Holyglizzy:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Holymajìk:BAAANQABCgIIAgAAAA==.',
Hy='Hypérîon:BAAANQAECgEIAQAAAA==.',
Ia='Iagging:BAAANQAECgcICwAAAA==.',
Ik='Ikiryo:BAEANQAECgEIAQAAAA==.',
Im='Imtuggdup:BAAANQAECgIIAwAAAA==.Imzachedup:BAAANQADCgUIBQAAAA==.',
In='Infidel:BAAANQAECgQIBQAAAA==.Invert:BAAANQADCgUIBQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgEIAQAAAA==.',
Ir='Irisharcher:BAAANQADCgcIBwAAAA==.Irishman:BAAANQADCgYICgAAAA==.',
It='Itazki:BAAANQAECgEIAQAAAA==.',
Ja='Jaft:BAAANQABCgQIBAAAAA==.Jalter:BAAANQAECgMIAwABNQAECgcICwABAAAAAA==.',
Je='Jediknight:BAAANQADCgEIAQAAAA==.Jenga:BAAANQAECgMIAwAAAA==.Jergal:BAAANQADCggIDwAAAA==.',
Jf='Jf:BAAANQAECgQIBQAAAA==.',
Ji='Jitzakkal:BAAANQAECggIDgAAAA==.',
Jo='Johnpaladin:BAAANQAECgQIBAAAAA==.Joshswims:BAAANQADCgcIBwAAAA==.',
Js='Js:BAAANQADCgQIBAAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kardinal:BAAANQAECgQIBAAAAA==.',
Ke='Keladorn:BAAANQADCgcIDQAAAA==.',
Kh='Khanyiso:BAAANQAECgEIAQAAAA==.',
Ki='Kieran:BAAANQAECgEIAQAAAA==.Kilsaurys:BAAANQAECgUIBQAAAA==.Kismete:BAAANQADCggICgABNQAECgMIAwABAAAAAA==.',
Ko='Konstantine:BAAANQADCgYICwAAAA==.',
Kr='Krittykitkat:BAAANQAECgIIAgAAAA==.',
La='Laprimera:BAAANQADCgIIAgAAAA==.Lazyjade:BAAANQAECgEIAQAAAA==.',
Lo='Lorynn:BAAANQAECgEIAQAAAA==.',
Ma='Madwe:BAAANQAECgIIAgAAAA==.Magturri:BAAANQAECgEIAQAAAA==.Mamameatmode:BAAANQADCgQIBAAAAA==.Marlbororeds:BAAANQAECgIIAgAAAA==.Maxfirepower:BAAANQADCgQIBQAAAA==.Maxsunward:BAAANQADCgYICwAAAA==.',
Me='Meepasaurus:BAAANQAECgQICAAAAA==.Mellky:BAAANQAECgQIBQAAAA==.Metanoia:BAAANQADCggIEAABNQAECgQIBAABAAAAAA==.',
Mi='Mib:BAEANQAECgQIBQAAAA==.Midnitetrvlr:BAAANQADCggIDgAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAAANQAECgIIAgAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAAANQAECgEIAgAAAA==.Monre:BAAANQAECgIIAgAAAA==.Moonflame:BAAANQAECgMIAwAAAA==.Mooriah:BAAANQAECgEIAQAAAA==.Motowa:BAAANQADCgYIBgAAAA==.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynchus:BAAANQADCgYIBwAAAA==.Mysterypala:BAAANQADCgYICwAAAA==.Mysteryvoke:BAAANQADCgYIBgAAAA==.',
Na='Naneko:BAAANQADCgcIBwAAAA==.',
Ne='Nehi:BAAANQAECggICAAAAA==.Neotahr:BAAANQAECgIIAwAAAA==.',
Ni='Nismoto:BAAANQAECgQIBQAAAA==.Nitehunter:BAAANQADCggIDgAAAA==.',
No='Noobert:BAAANQABCgIIAwAAAA==.Novademic:BAAANQADCgYICAAAAA==.',
Og='Ognikkay:BAAANQAECgQIBQAAAA==.',
Pa='Pallyana:BAAANQAECgEIAQAAAA==.',
Pe='Perridan:BAAANQADCgcIDAAAAA==.',
Pi='Pinkponyclub:BAAANQAECgEIAQAAAA==.Pinkyshock:BAAANQAECgMIBQAAAA==.',
Pr='Praystatiøn:BAAANQADCgYIBgAAAA==.',
Pu='Purplod:BAAANQAECgIIAgAAAA==.',
Py='Pyatpree:BAAANQADCgQIBQAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
Qi='Qing:BAAANQAECgIIAgAAAA==.',
Qy='Qybxboogies:BAAANQAECgMIAwAAAA==.',
Ra='Raensong:BAAANQADCgYICwAAAA==.Raisa:BAAANQAECgEIAgAAAA==.Rakarum:BAAANQADCgcIBwAAAA==.Rasar:BAAANQADCggICAAAAA==.Rathew:BAAANQADCgYICAAAAA==.Rawnext:BAAANQAECgEIAQAAAA==.',
Re='Revoker:BAAANQAECgMIBQAAAA==.',
Ri='Riddlez:BAAANQAECgQIBQAAAA==.',
Ro='Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECgMIAwAAAA==.Rox:BAAANQADCgcIBwAAAA==.',
['Ré']='Réîgn:BAAANQADCggICQAAAA==.',
Sa='Sacrus:BAAANQADCgEIAQAAAA==.Sarah:BAAANQAFFAEIAQAAAA==.',
Sc='Scalelord:BAAANQADCgQIBQAAAA==.Scoobear:BAAANQAECgMIAwAAAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senjougahara:BAAANQAECgcICwAAAA==.Seriyah:BAAANQAECgUICQAAAA==.',
Sh='Shabane:BAAANQADCgYICwAAAA==.Shame:BAAANQAECgIIAwAAAA==.Shinobi:BAAANQADCgcIDQAAAA==.Shirls:BAAANQAECgIIAgAAAA==.Shivak:BAAANQAECgQIBAAAAA==.Shivanie:BAAANQADCggIEAAAAA==.Shock:BAAANQAECgQIBQAAAA==.Shredderella:BAAANQAECgIIAgAAAA==.Shrug:BAAANQAECgIIAgAAAA==.',
Sk='Skeeda:BAAANQADCgcIFAAAAA==.Skylinex:BAAANQADCggIDgAAAA==.Skïttles:BAAANQAECgEIAQAAAA==.',
Sl='Sleezball:BAAANQAECgIIAgAAAA==.',
So='Softie:BAAANQADCgMIAwAAAA==.Sonictide:BAAANQAECgEIAgAAAA==.Soulscream:BAAANQADCgcIBwAAAA==.',
Sp='Spaghetto:BAAANQAECgEIAQAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgUIBQAAAA==.',
Su='Suzel:BAAANQADCgQIBAAAAA==.',
Sy='Synder:BAAANQAECgEIAQAAAA==.',
Ta='Tainin:BAAANQADCgYIDAAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQADCgMIBAAAAA==.Tarynna:BAAANQADCgYIDAAAAA==.Tazerface:BAAANQAECgEIAQAAAA==.',
Te='Tekin:BAAANQAECgEIAQAAAA==.Teleprompter:BAAANQADCgEIAQAAAA==.Telrissan:BAAANQADCggICQAAAA==.Tenyroldemon:BAAANQADCgcICQAAAA==.',
Th='Thald:BAAANQAECgEIAQAAAA==.',
Ti='Tinytip:BAAANQADCgYIBgAAAA==.Tisakna:BAAANQAECgQIBQAAAA==.',
To='Tool:BAAANQADCgYIBgAAAA==.',
Tr='Trask:BAAANQAECgIIAgAAAA==.Trokom:BAAANQAECgYICgAAAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAAANQAECgQIBQAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ur='Urbanmech:BAAANQAECgEIAQAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Vandermark:BAAANQAECgQIBQAAAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Vidrus:BAAANQADCgYIBgAAAA==.Vilkas:BAAANQABCgIIAQABNQAECgYICQABAAAAAA==.Viserion:BAAANQADCgYIBgAAAA==.',
Wa='Waddledoo:BAAANQAECgIIAgAAAA==.Warmaku:BAAANQADCggIDgAAAA==.',
Wi='Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAAANQAECgQIBQAAAA==.Xanyp:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Xe='Xerg:BAAANQABCgQIBAABNQAECgIIAgABAAAAAA==.',
Xi='Xinaveruk:BAAANQADCggIBwAAAA==.',
Xo='Xoro:BAAANQADCgQIBAAAAA==.',
Xr='Xrxyz:BAAANQADCgEIAQAAAA==.',
Xs='Xshamster:BAAANQAECgQIBgAAAA==.',
Ye='Yewna:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.',
Za='Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgUIBwAAAA==.Zau:BAAANQAECgIIAgAAAA==.',
Zo='Zolja:BAAANQADCgYICQAAAA==.Zoney:BAAANQADCgMIAwAAAA==.Zordlon:BAAANQAECgEIAQAAAA==.',
Zu='Zukem:BAAANQAECgQIBgAAAA==.Zulelphie:BAAANQADCgEIAQAAAA==.',
Zy='Zyariah:BAAANQABCgMIAwAAAA==.Zyvea:BAAANQADCggIDgAAAA==.',
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
