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

local lookup = {'Unknown-Unknown','Mage-Arcane','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','Hunter-BeastMastery',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Adrua:BAAANQADCgUIBgAAAA==.Adym:BAAANQAECgUIBwAAAA==.',
Ag='Agave:BAAANQAECgQIBQAAAA==.',
Ai='Aiyah:BAAANQAECgIIAgAAAA==.',
Al='Altarboi:BAAANQADCggIEwAAAA==.Alüçard:BAAANQAECgEIAQAAAA==.',
Am='Amoraniel:BAAANQAECgUICAAAAA==.',
An='Anavar:BAAANQAECgYIBgAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAAANQAECgIIAgAAAA==.Andresra:BAAANQAECggIEAAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAAANQAECgQIBgAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.',
As='Asterin:BAAANQADCgIIAgAAAA==.',
Av='Avâtre:BAAANQADCgcIDQAAAA==.',
Ba='Baguette:BAAANQAECgUIBwAAAA==.Bajingobomb:BAAANQAECgQIBQAAAA==.Bakblood:BAAANQABCgQIBgAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.',
Be='Be:BAAANQAECgIIAgAAAA==.Beckyoncé:BAAANQAECgQIBQAAAA==.Bedris:BAAANQAECgEIAQAAAA==.Beerticus:BAAANQAECgMIBAAAAA==.',
Bi='Bigdingus:BAAANQAECgUIBwAAAA==.Binggles:BAABNQAFFIEJAAICAAUJ/RfLAQDiAQACAAUJ/RfLAQDiAQAAAA==.',
Bl='Blacksheep:BAAANQADCggICgAAAA==.Blôôðhôôf:BAAANQADCgQIBAAAAA==.',
Bo='Bomboclaat:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Boolay:BAAANQAECgEIAQABNQABCgUIBQABAAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQADCgUIBQAAAA==.Bosmina:BAAANQAECgYICwAAAA==.',
Br='Braei:BAAANQAECgIIAgAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Brenmonk:BAAANQADCggIFgAAAA==.Brenpriest:BAAANQADCgYIBgAAAA==.',
Bu='Bubblebaddie:BAAANQADCggIEgAAAA==.Bubblicous:BAAANQADCgYIBgAAAA==.Bugenhagen:BAAANQAECgYICwAAAA==.Butchers:BAAANQADCgUIBgAAAA==.Buttpaladin:BAAANQAECgMIBgAAAA==.',
Ca='Cardib:BAABNQAECoEZAAIDAAkJISQqAgCrAwADAAkJISQqAgCrAwAAAA==.Cavos:BAAANQAECgUICAAAAA==.',
Ce='Cernsarn:BAAANQAECgEIAgAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Chiri:BAEANQAECgcIDQAAAA==.Chvngus:BAAANQAECgMIBAAAAA==.',
Ci='Citizencain:BAAANQAECgMIAwAAAA==.',
Cl='Claytnbigsby:BAAANQAECgEIAgAAAA==.',
Co='Cogswell:BAAANQADCgUIBQAAAA==.Condor:BAEANQAECggIAwAAAA==.Coohwhip:BAAANQADCgQIBAAAAA==.',
Cr='Crakidos:BAAANQADCgQIBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAAANQADCggIDQAAAA==.Cristobal:BAAANQAECgQIBAAAAA==.Crunkshot:BAAANQADCgEIAQAAAA==.',
Cy='Cydea:BAAANQAECgEIAQAAAA==.',
Da='Dagidan:BAAANQAECgYICwAAAA==.',
De='Dead:BAAANQADCggICAAAAA==.Demontotems:BAAANQADCgYIBgAAAA==.Demotoxi:BAAANQAECgMIBgAAAA==.Deriso:BAAANQAECgUIBQAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCgYICwABAAAAAA==.Destrozinth:BAAANQAECgUIBQAAAA==.Dethorok:BAAANQAECgQIBgAAAA==.Deåth:BAAANQADCgYIDQAAAA==.',
Di='Diagonpally:BAAANQADCgUICQABNQAECgYICwABAAAAAA==.Digey:BAAANQAECgQIBQAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAAANQAECgIIAwAAAA==.',
Do='Dontlookatme:BAAANQABCgUIBQAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCgMIBAABNQADCgYIDQABAAAAAA==.',
Dr='Drakbek:BAAANQADCggIEgAAAA==.Dreadshot:BAAANQADCgYIBgAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dronebot:BAAANQAECgUIDwAAAA==.Drucifer:BAAANQADCggIDwAAAA==.',
Du='Durros:BAAANQADCggIFgAAAA==.',
Eb='Eboger:BAAANQADCggICAAAAA==.',
Em='Embody:BAAANQAECgEIAQAAAA==.',
En='Endlyss:BAAANQAECgUIBQAAAA==.',
Er='Erasmas:BAAANQAECgEIAQAAAA==.Erzascarlét:BAAANQAECgYICwAAAA==.',
Eu='Euphoricx:BAAANQAECgYICwAAAA==.',
Ev='Evildeader:BAAANQADCggIDgABNQADCggIEgABAAAAAA==.Eviltotems:BAAANQADCggIEgAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAAANQAECgYICwAAAA==.Fantasma:BAAANQADCgYICQAAAA==.',
Fe='Fear:BAAANQAECgIIAgAAAA==.',
Fi='Findal:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Fistymoo:BAEANQADCgMIAwABNQAECgcIDQABAAAAAA==.Fivemagics:BAAANQAECgEIAQAAAA==.',
Fl='Fleaboy:BAAANQAECgMIBgAAAA==.Flist:BAAANQAECgQIBAAAAA==.Floof:BAAANQADCgYICQAAAA==.',
Fo='Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAAANQAECgEIAQAAAA==.Freesia:BAAANQADCgYIBgAAAA==.',
Fx='Fxce:BAAANQAECgQIBAAAAA==.',
Ga='Gaothan:BAAANQADCgYIBgAAAA==.',
Gh='Ghulz:BAAANQAECgcIDgAAAA==.',
Gi='Gibsmedats:BAAANQAECgQIBQAAAA==.',
Gl='Glaiven:BAAANQAECgUIBwAAAA==.Glasscleaner:BAAANQAECgUICQABNQAECgcIEgABAAAAAA==.Glenmorangie:BAAANQAECgEIAQAAAA==.',
Gn='Gnartusk:BAAANQAECgIIAgAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.',
Gr='Greens:BAAANQAECgIIAgAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Grillvy:BAAANQADCgIIBQAAAA==.Grumbo:BAAANQADCgYIBgAAAA==.Grïma:BAAANQAECgYICwAAAA==.',
Gu='Gueritestje:BAAANQAECgQIBgAAAA==.Guzzlord:BAAANQAECgUIBwAAAA==.',
Ha='Halfman:BAAANQAECgEIAQAAAA==.',
Hb='Hboozing:BAAANQAECgMIBgAAAA==.',
He='Heayt:BAAANQABCgIIBAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Hipdrop:BAAANQAECgMIAwAAAA==.Hitoshura:BAAANQAECgQIBQAAAA==.',
Ho='Holyginger:BAAANQADCggIEQAAAA==.Holyglizzy:BAAANQADCggICAABNQAECgMIBgABAAAAAA==.Holymajìk:BAAANQABCgIIAwAAAA==.',
Hy='Hypérîon:BAAANQAECgQIBQAAAA==.',
Ia='Iagging:BAAANQAECgcIEgAAAA==.',
Ik='Ikiryo:BAEANQAECgIIAwAAAA==.',
Im='Imtuggdup:BAAANQAECgUICAAAAA==.Imzachedup:BAAANQADCgUIBQAAAA==.',
In='Infidel:BAAANQAECgUICgAAAA==.Invert:BAAANQADCgUIBQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgEIAgAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irisharcher:BAAANQADCgcICwAAAA==.Irishman:BAAANQADCgYIEAAAAA==.',
It='Itazki:BAAANQAECgEIAgAAAA==.',
Ja='Jaft:BAAANQABCgQIBAAAAA==.Jalter:BAAANQAECgcICQABNQAECgcIEgABAAAAAA==.',
Je='Jediknight:BAAANQADCgEIAQAAAA==.Jenga:BAAANQAECgMIAwAAAA==.Jergal:BAAANQAECgQIBAAAAA==.',
Jf='Jf:BAAANQAECgYICwAAAA==.',
Ji='Jitzakkal:BAABNQAECoEZAAMEAAkJKyQGBgB9AgAFAAcJwh+bDACsAgAEAAYJZCQGBgB9AgAAAA==.',
Jn='Jn:BAAANQADCgYIBgAAAA==.',
Jo='Johnpaladin:BAAANQAECgYICgAAAA==.Joshswims:BAAANQADCgcIBwAAAA==.',
Js='Js:BAAANQADCgYICgAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.Juleita:BAAANQABCgQIBAAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kardinal:BAAANQAECgcICwAAAA==.',
Ke='Keladorn:BAAANQAECgEIAQAAAA==.',
Kh='Khanyiso:BAAANQAECgQIBQAAAA==.Kharak:BAAANQAECgQIBAAAAA==.',
Ki='Kichii:BAAANQADCgEIAQAAAA==.Kieran:BAAANQAECgQIBQAAAA==.Kilsaurys:BAAANQAECgcIDAAAAA==.Kirakishou:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.Kismete:BAAANQAECgMIAwAAAA==.',
Ko='Konstantine:BAAANQAECgEIAQAAAA==.',
Kr='Krittykitkat:BAAANQAECgIIAgABNQAECgYIBgABAAAAAA==.Kryptocron:BAAANQABCgYICgAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
['Kí']='Kítsune:BAAANQADCgYICgAAAA==.',
La='Laprimera:BAAANQADCgUIBwAAAA==.Lasticon:BAAANQADCgcIAQAAAA==.Lazyjade:BAAANQAECgQIBAAAAA==.',
Le='Leyline:BAAANQADCgYIBgAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.',
Lo='Lorynn:BAAANQAECgQIBQAAAA==.',
Ma='Madwe:BAAANQAECgIIAgAAAA==.Magturri:BAAANQAECgQIBQAAAA==.Majìkstik:BAAANQABCgEIAQAAAA==.Mamameatmode:BAAANQAECgMIAwAAAA==.Marlbororeds:BAAANQAECgQIBAAAAA==.Maxfirepower:BAAANQADCgYICwAAAA==.Maxsunward:BAAANQADCgcIEgAAAA==.',
Me='Meepasaurus:BAAANQAECgUIDQAAAA==.Megaforce:BAAANQAECgEIAQAAAA==.Mellky:BAAANQAECgYICwAAAA==.Metanoia:BAAANQAECgYIBgABNQAECgcICwABAAAAAA==.',
Mi='Mib:BAEANQAECgYICgABNQAECggIAwABAAAAAA==.Mibb:BAEANQAECggIBgABNQAECggIAwABAAAAAA==.Midnitetrvlr:BAAANQAECgQIBAAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAAANQAECgUIBwAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAAANQAECgYICAAAAA==.Monre:BAAANQAECgMIBQAAAA==.Moonflame:BAAANQAECgYICQAAAA==.Mooriah:BAAANQAECgQIBQAAAA==.Mordekhuul:BAAANQAECgYIBgAAAA==.Motowa:BAAANQADCgYIBgAAAA==.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynchus:BAAANQADCgcICgAAAA==.Mysterydh:BAAANQADCgYIBgAAAA==.Mysterypala:BAAANQAECgIIAgAAAA==.Mysteryvoke:BAAANQAECgEIAQAAAA==.',
Na='Naneko:BAAANQAECgEIAQAAAA==.',
Ne='Nehi:BAAANQAECggICAAAAA==.Neotahr:BAAANQAECgYICQAAAA==.',
Ni='Nickiminajj:BAAANQAECgcIBwAAAA==.Nismoto:BAAANQAECgYICwAAAA==.Nitehunter:BAAANQAECgIIAgAAAA==.',
No='Noobert:BAAANQAECgEIAQAAAA==.Novademic:BAAANQADCgYICAAAAA==.',
['Nö']='Növacaïn:BAAANQADCgEIAQAAAA==.',
Og='Ognikkay:BAAANQAECgYICwAAAA==.',
Pa='Pabiloneta:BAAANQADCgYIBgAAAA==.Pallyana:BAAANQAECgQIBQAAAA==.',
Pe='Perridan:BAAANQADCggIFAAAAA==.',
Ph='Phalandrel:BAAANQAECggIAQAAAA==.',
Pi='Pinkponyclub:BAAANQAECgQIBQAAAA==.Pinkyshock:BAAANQAECgUIDwAAAA==.',
Po='Pog:BAAANQADCgQIBAAAAA==.Portholes:BAAANQADCgQIBAAAAA==.',
Pr='Praystatiøn:BAAANQADCgYIBgAAAA==.',
Ps='Psyop:BAAANQAECgQIBAAAAA==.',
Pu='Purplod:BAAANQAECgUIBwAAAA==.',
Py='Pyatpree:BAAANQADCgUIBwAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
Qi='Qing:BAAANQAECgQIBgAAAA==.',
Qy='Qybxboogies:BAAANQAECgMIAwAAAA==.',
Ra='Raensong:BAAANQADCgYICwAAAA==.Rainingarrow:BAAANQABCgIIAwAAAA==.Raisa:BAAANQAECgUIBwAAAA==.Rakarum:BAAANQAECgEIAQAAAA==.Rasar:BAAANQAECgQIBAAAAA==.Rathew:BAAANQAECgQIBAAAAA==.Rawnext:BAAANQAECgYIBwAAAA==.',
Re='Revenger:BAAANQABCgEIAQAAAA==.Revoker:BAAANQAECgUIDwAAAA==.',
Ri='Riddlez:BAAANQAECgYICwAAAA==.',
Ro='Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECgUIBwAAAA==.Rox:BAAANQAECgEIAQAAAA==.',
['Ré']='Réîgn:BAAANQAECgMIAwAAAA==.',
Sa='Sacrus:BAAANQADCgEIAQAAAA==.Sarah:BAABNQAECoEYAAMGAAkJcyL/AgB1AwAGAAkJcyL/AgB1AwAHAAEJcxAljQBJAAAAAA==.',
Sc='Scalelord:BAAANQADCgYICwAAAA==.Scoobear:BAAANQAECgMIBgAAAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQADCgQIBAAAAA==.Senjougahara:BAAANQAFFAEIAQAAAA==.Seriyah:BAAANQAECgcIEAAAAA==.',
Sh='Shabane:BAAANQAECgIIAgAAAA==.Shame:BAAANQAECgYICQAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shirls:BAAANQAECgUIBwAAAA==.Shivak:BAAANQAECgYICgAAAA==.Shivanie:BAAANQADCggIFQAAAA==.Shock:BAAANQAECgQICQAAAA==.Shredderella:BAAANQAECgUIBwAAAA==.Shrug:BAAANQAECgUIBwAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwABAAAAAA==.',
Sk='Skeeda:BAAANQADCggIHAAAAA==.Skylinex:BAAANQAECgUIBQAAAA==.Skylinez:BAAANQADCgYIDAAAAA==.Skïttles:BAAANQAECgMIBAAAAA==.',
Sl='Sleezball:BAAANQAECgQIBgAAAA==.',
So='Softie:BAAANQADCgUICAAAAA==.Sonictide:BAAANQAECgEIAwAAAA==.Soulscream:BAAANQADCggICwAAAA==.',
Sp='Spaghetto:BAAANQAECgMIBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgUICAAAAA==.',
Su='Suzel:BAAANQADCggIDAAAAA==.',
Sy='Synder:BAAANQAECgQIBQAAAA==.',
Ta='Tainin:BAAANQAECgIIAgAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAQAAAA==.Tarynna:BAAANQAECgIIAgAAAA==.Tazerface:BAAANQAECgIIAwAAAA==.',
Te='Tekin:BAAANQAECgQIBQAAAA==.Teleprompter:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Telrissan:BAAANQAECgEIAQAAAA==.Tenyroldemon:BAAANQAECgEIAQAAAA==.',
Th='Thald:BAAANQAECgQIBQAAAA==.',
Ti='Timzilla:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.Tinytip:BAAANQADCgYIBgAAAA==.Tisakna:BAAANQAECgYICwAAAA==.',
To='Tool:BAAANQADCgYIBgAAAA==.Tostitos:BAAANQADCggICQAAAA==.',
Tr='Trask:BAAANQAECgUIBwAAAA==.Trokom:BAAANQAECgcIEQAAAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAAANQAECgYICwAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ur='Urbanmech:BAAANQAECgUIBgAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Vandermark:BAAANQAECgYICwAAAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIBQAAAA==.Vidrus:BAAANQADCgcIDQAAAA==.Vilkas:BAAANQAECggIEQAAAA==.Viserion:BAAANQADCgYIDAAAAA==.',
Wa='Waddledoo:BAAANQAECgUIBwAAAA==.Warmaku:BAAANQAECgMIAwAAAA==.',
Wi='Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAAANQAECgcIDAAAAA==.Xanyp:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.',
Xe='Xerg:BAAANQABCgYICgABNQAECgQIBgABAAAAAA==.',
Xi='Xinaveruk:BAAANQADCggIDwAAAA==.',
Xo='Xoro:BAAANQAECgEIAQAAAA==.',
Xr='Xrxyz:BAAANQADCgEIAQAAAA==.',
Xs='Xshamster:BAAANQAECgYIDAAAAA==.',
Ye='Yewna:BAAANQADCgYICwABNQAECgYICwABAAAAAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zau:BAAANQAECgUIBwAAAA==.',
Zo='Zolja:BAAANQADCggIEQAAAA==.Zoney:BAAANQADCgMIAwAAAA==.Zordlon:BAAANQAECgEIAQAAAA==.',
Zu='Zukem:BAAANQAECgcIDQAAAA==.Zulelphie:BAAANQADCgEIAQAAAA==.',
Zy='Zyariah:BAAANQABCgQIBQAAAA==.Zyvea:BAAANQAECgIIAgAAAA==.',
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
