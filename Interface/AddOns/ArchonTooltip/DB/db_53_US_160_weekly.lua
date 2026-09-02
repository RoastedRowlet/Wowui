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
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=53,date='2026-09-01',data={Ae='Aeropunk:BAAANQADCgIIAgAAAA==.Aerys:BAAANQAECgMIAwAAAA==.',
Aj='Ajaxprime:BAAANQADCgIIAgAAAA==.',
Ak='Akiojonës:BAAANQADCgYIBgAAAA==.',
Al='Alesîa:BAAANQADCgUICgAAAA==.Alzim:BAAANQAECgYICgAAAA==.',
An='Angry:BAAANQADCgQIBAAAAA==.Ankelbiter:BAAANQADCggIDgAAAA==.Anûbis:BAAANQADCgYIBgAAAA==.',
Ar='Aragos:BAAANQADCggIDAAAAA==.Arcelon:BAAANQADCgYICwAAAA==.Arwenatak:BAAANQAECgEIAQAAAA==.',
At='Athren:BAAANQADCggIDgAAAA==.',
Av='Avanorina:BAAANQADCggIEAAAAA==.',
Ba='Baksylyk:BAAANQADCgYICwABNQADCgcIDAABAAAAAA==.Ballador:BAAANQADCgcIDQAAAA==.Barakoshamma:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Barazudar:BAAANQAECgMIAwAAAA==.Baroke:BAAANQADCgYIBgAAAA==.Barreta:BAAANQAECgEIAQAAAA==.',
Be='Beck:BAAANQAECgMIAwAAAA==.Beefykin:BAAANQADCgYICAAAAA==.Bellámuerté:BAAANQADCgcIDAAAAA==.Bemmy:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Bi='Bigdrandyy:BAAANQAECgEIAQAAAA==.Biggspal:BAAANQADCgYIBgAAAA==.',
Bl='Blackbird:BAAANQAECgIIAgAAAA==.Blackmage:BAAANQADCgYIBgAAAA==.Bloodlordzz:BAAANQAECgIIAgAAAA==.Bloodreina:BAAANQAECgQIBQAAAA==.',
Bo='Bob:BAAANQADCgcIDAAAAA==.Bockandcalls:BAAANQAECgEIAQAAAA==.Bolbi:BAAANQAECgEIAQAAAA==.',
Br='Breadnbudda:BAAANQADCgYIBgAAAA==.Brogar:BAAANQADCgYIBgAAAA==.',
Bu='Bulkam:BAAANQADCggIDQAAAA==.Bulkazarr:BAAANQAECgQIBAAAAA==.',
Ca='Callabash:BAAANQAECgEIAQAAAA==.',
Ce='Celarena:BAAANQADCggIDQAAAA==.',
Ch='Chilla:BAAANQADCgQIBAAAAA==.Chopzzpala:BAAANQADCgYIBwAAAA==.Chyp:BAAANQAECgIIAgAAAA==.',
Ci='Cichorì:BAAANQAFFAIIAgAAAA==.Cipa:BAAANQADCgcIBwAAAA==.Circee:BAAANQADCgYIBwAAAA==.',
Co='Colmer:BAAANQADCgMIAwAAAA==.',
Cr='Creckko:BAAANQABCgMIAwAAAA==.Crockito:BAAANQAFFAIIAwAAAA==.',
Cy='Cyrusdavirus:BAAANQADCgUIBQAAAA==.',
Da='Dabu:BAAANQADCgIIAgAAAA==.Danto:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Darktroll:BAAANQAECgMIAwAAAA==.',
De='Depoprovera:BAAANQAECgUIBgAAAA==.Deqz:BAAANQAECgMIAgAAAA==.',
Di='Diezel:BAAANQADCgYIBgAAAA==.Dilox:BAAANQADCgYIDAAAAA==.Dinosaur:BAAANQAECgUIBwAAAA==.Dirtydee:BAAANQAECgEIAQAAAA==.Disaaya:BAAANQAECgIIAgAAAA==.',
Do='Dontos:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Doodlebug:BAAANQAECgYICAAAAA==.Dotsntaxes:BAAANQAECgcICAAAAA==.',
Dr='Dracuujin:BAAANQADCggICAABNQAECgcICwABAAAAAA==.Dralioli:BAAANQADCggIDgAAAA==.Dreanil:BAAANQADCgUIBQAAAA==.Droho:BAAANQAECgQIBAABNQAFFAEIAgABAAAAAA==.Drroog:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.',
Du='Dumper:BAAANQADCgQIBAAAAA==.',
Dw='Dwarfsize:BAAANQADCggICAABNQAECggIDgABAAAAAA==.',
['Dâ']='Dârn:BAAANQAECgMIAwAAAA==.',
El='Eleweaver:BAAANQADCgUIBgAAAA==.Elissra:BAAANQADCgEIAQABNQADCggIDwABAAAAAA==.Elvispræstly:BAAANQADCgYIBgAAAA==.',
En='Enoughtalk:BAAANQADCgcICwAAAA==.',
Eo='Eostre:BAAANQAECgEIAQAAAA==.',
Eu='Eupherine:BAAANQAECgMIAwAAAA==.',
Ev='Evilpaladin:BAAANQAECgIIAgAAAA==.',
Ez='Ezluz:BAAANQAECgQIBAAAAA==.',
Fa='Facsimile:BAAANQAECgIIAgAAAA==.',
Fe='Festers:BAAANQADCgYIBgAAAA==.',
Fi='Fingerwalk:BAAANQADCggIDgAAAA==.',
Fl='Flappi:BAAANQADCggIDgAAAA==.Flappii:BAAANQADCgEIAQAAAA==.Fluffykat:BAAANQAECgMIAwAAAA==.',
Fo='Fosho:BAAANQAFFAEIAgAAAA==.',
Fr='Franch:BAAANQADCggIDgAAAA==.Frank:BAAANQADCgYICwAAAA==.Froddy:BAAANQADCggIDgAAAA==.Frylockk:BAAANQAECgQIBAAAAA==.',
Fu='Furrykane:BAEANQAECgEIAQAAAA==.Future:BAAANQAECgIIAgAAAA==.',
Ga='Gamepunisher:BAAANQAECgMIAwAAAA==.Gares:BAAANQAECgEIAQAAAA==.',
Gi='Giorbs:BAAANQADCgYIBgAAAA==.',
Go='Goham:BAAANQAECgEIAQAAAA==.Goobe:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.Gorro:BAAANQADCgYIBgAAAA==.',
Gr='Grogon:BAAANQADCgQIBAAAAA==.Gromlo:BAAANQAECgMIAwAAAA==.Grulog:BAAANQADCgUICQAAAA==.',
Gu='Gunny:BAAANQAECgMIAwAAAA==.',
['Gã']='Gã:BAAANQADCgUIBQAAAA==.',
Ha='Haileigh:BAAANQADCgUIBgAAAA==.Havöc:BAAANQAECgIIAgAAAA==.',
Hi='Hikawa:BAAANQAECgEIAQAAAA==.Hippocratic:BAAANQADCggIDQAAAA==.',
Ho='Holybeefalo:BAAANQADCggICAAAAA==.',
Hu='Huntemall:BAAANQADCggIDgAAAA==.',
Hy='Hysteriix:BAEANQAECgQIBAAAAA==.',
Ic='Iceshards:BAAANQADCggIDgAAAA==.Icraptotems:BAAANQADCggIDgAAAA==.',
Il='Illidankior:BAAANQAECgEIAQAAAA==.',
Im='Imen:BAAANQAECgEIAQAAAA==.Imsassy:BAAANQADCgUIBgAAAA==.',
In='Inmortuae:BAAANQADCgQIBgABNQAECgEIAQABAAAAAA==.',
Io='Iornbane:BAAANQADCgYIBQAAAA==.',
Ir='Irissela:BAAANQADCgUIBwAAAA==.',
Iv='Ivalice:BAAANQAECgIIAgAAAA==.',
Ja='Jafbe:BAAANQADCgQIBAAAAA==.Jaghatai:BAAANQADCgcIBwAAAA==.',
Ji='Jimcarrey:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.Jimmyc:BAAANQAECgEIAQAAAA==.Jimmysi:BAAANQADCgYICAAAAA==.',
Jo='Joemauma:BAAANQAECgEIAQAAAA==.',
Jp='Jpam:BAAANQAECgQIBQAAAA==.',
Ju='Jumbosize:BAAANQAECggIDgAAAA==.Jupîter:BAAANQADCgEIAQAAAA==.Justamuslim:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Ka='Kaerlif:BAAANQADCgcIBgABNQAECgYICQABAAAAAA==.Kalastrian:BAAANQADCggIDgAAAA==.Karateshock:BAAANQAECgIIAgAAAA==.Kazuren:BAAANQAECgEIAQAAAA==.',
Ke='Keano:BAAANQADCgUIBwAAAA==.Keeldemall:BAAANQADCgIIAgAAAA==.',
Ki='Kirin:BAAANQADCggICQAAAA==.',
Kl='Klaye:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Ko='Kodabonk:BAAANQAECgMIAwAAAA==.Kodanorth:BAAANQADCgUICAABNQAECgMIAwABAAAAAA==.Korthos:BAAANQADCggIDgAAAA==.Kotara:BAAANQADCgYIBwAAAA==.',
Kr='Kraur:BAAANQAECgEIAQAAAA==.',
['Kì']='Kìngpin:BAAANQAECgIIAgAAAA==.',
La='Lammp:BAAANQAECgQIBQAAAA==.Lazydragon:BAAANQAECgQIBAAAAA==.',
Li='Liaeda:BAAANQAECgEIAQAAAA==.Lianshi:BAAANQADCgUIBQAAAA==.Linainverse:BAAANQADCgYICwAAAA==.',
Lo='Loosie:BAAANQADCgEIAQAAAA==.Lost:BAAANQADCgUIBQAAAA==.Lovely:BAAANQADCgQIBAAAAA==.',
Lu='Luduhcris:BAAANQADCgQIBAAAAA==.Lugnuts:BAAANQAECgMIAwAAAA==.Lumiltiand:BAAANQAECgcIDQAAAA==.',
Ma='Makloy:BAAANQABCgIIAgAAAA==.Malgrendin:BAAANQAECgQIBwAAAA==.Malty:BAAANQAECgMIAwAAAA==.Malédictias:BAAANQADCgYICgAAAA==.Manataurus:BAAANQADCgYIBgAAAA==.Manuall:BAAANQADCggIDgAAAA==.Marbas:BAAANQADCggIDgAAAA==.Maxidk:BAAANQAECgIIAwAAAA==.',
Mi='Midgemaisel:BAAANQADCgYICwAAAA==.Mik:BAAANQABCgMIAgABNQADCgEIAQABAAAAAA==.Mikhael:BAAANQADCgEIAQAAAA==.Mirado:BAAANQAECgMIAwAAAA==.Mirix:BAAANQADCgEIAQAAAA==.Mithridates:BAAANQAECgEIAQAAAA==.',
Mo='Molonlabe:BAAANQADCgUIBQAAAA==.Monix:BAAANQADCgYIDAAAAA==.Monkragga:BAAANQADCggIDgAAAA==.Mooseleroy:BAAANQAECgEIAQAAAA==.Mortarien:BAAANQAECgEIAQAAAA==.Mozai:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.',
Mu='Mugged:BAAANQAECgEIAQAAAA==.',
My='Myrtle:BAAANQADCggIDQAAAA==.',
['Má']='Másóchist:BAAANQADCgIIAgAAAA==.',
Ni='Nice:BAAANQADCgYIBgAAAA==.Nightveil:BAAANQAECgQIBQAAAA==.Niwatori:BAAANQAECgMIAwAAAA==.',
No='Noah:BAAANQAFFAEIAQAAAA==.Nol:BAAANQABCgIIAgABNQAFFAEIAQABAAAAAA==.Nolarz:BAAANQAFFAEIAQAAAA==.',
Nu='Nukthom:BAAANQADCgcICQAAAA==.',
Ny='Nyneaves:BAAANQAECgQIBQAAAA==.Nyst:BAAANQAECgQIBAAAAA==.',
Ob='Objekt:BAAANQAECgEIAQAAAA==.',
Oh='Ohmenwah:BAAANQADCgUICQAAAA==.',
Oj='Ojplosion:BAAANQAECgMIAwAAAA==.',
Om='Omghunter:BAAANQABCgIIAwAAAA==.',
On='Onisprite:BAAANQADCggIDgAAAA==.',
Or='Orchaos:BAAANQADCgEIAQAAAA==.Ordhah:BAAANQADCgcIDAAAAA==.',
Os='Osanna:BAAANQADCgUIBQAAAA==.',
Pa='Paladout:BAAANQAECgMIAwAAAA==.Palletjack:BAAANQAECgMIAwAAAA==.Palli:BAAANQADCgQICAAAAA==.Paona:BAAANQAECgEIAQAAAA==.Papafloppa:BAAANQADCgIIAgAAAA==.',
Pe='Peraroll:BAAANQADCggICAAAAA==.',
Ph='Phenphen:BAAANQAECggICAAAAA==.',
Pl='Planetdru:BAAANQAECgIIAgAAAA==.',
Po='Popshampain:BAAANQADCggICAAAAA==.',
Pu='Punchydabear:BAAANQADCggICwAAAA==.',
Ra='Ratscum:BAEANQADCgcIBwAAAA==.Rayssa:BAAANQAECgIIAgAAAA==.',
Re='Redeker:BAAANQAECgEIAQAAAA==.Reyna:BAAANQADCgQIBAAAAA==.',
Rh='Rholand:BAAANQADCgQIBQAAAA==.',
Ri='Ricopsu:BAAANQAECgMIAwAAAA==.',
Rn='Rngnar:BAAANQADCgUIBQAAAA==.',
Ro='Rocklii:BAAANQADCgUIBQAAAA==.Roguewolf:BAAANQAECgMIAwAAAA==.Roki:BAAANQAECgEIAQAAAA==.Rolow:BAAANQAECgIIAgAAAA==.Roony:BAAANQAFFAEIAQAAAA==.Rot:BAAANQAECgQIBAAAAA==.Royle:BAAANQABCgIIAgAAAA==.',
Ru='Runnerjay:BAAANQADCgYIBwABNQAECgUIBgABAAAAAA==.',
Ry='Rysxn:BAAANQAECgEIAQAAAA==.Ryuujins:BAAANQAECgcICwAAAA==.',
Sa='Sago:BAAANQAECgEIAQAAAA==.',
Sc='Scyon:BAAANQAECgcICwAAAA==.',
Se='Selinie:BAAANQABCgQIBgAAAA==.Senari:BAAANQAECgEIAQAAAA==.Senbane:BAAANQADCggICQAAAA==.',
Sh='Shadowblazer:BAAANQAECgQIBAAAAA==.Shalizar:BAAANQADCgMIAwAAAA==.Shanda:BAAANQAECgYICgAAAA==.Shanto:BAAANQAECgEIAQAAAA==.Sheesh:BAAANQADCgcIDgAAAA==.Shoumei:BAAANQAECgMIAwAAAA==.',
Si='Silfra:BAAANQADCggIDAAAAA==.',
Sk='Skolaid:BAAANQAECgcICQAAAA==.',
Sm='Smilingdev:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.Smoopoodoop:BAAANQADCgYICQAAAA==.',
So='Soulmend:BAAANQADCggIDQAAAA==.',
Sp='Spaceman:BAAANQADCgcIBwAAAA==.',
Sq='Sqûïsh:BAAANQADCggICAAAAA==.',
St='Stabbz:BAAANQADCgUIBQAAAA==.Stevetson:BAAANQADCgYICAAAAA==.Stoops:BAAANQADCggIDgAAAA==.Stormdemon:BAAANQADCggIDgAAAA==.Stormspellz:BAAANQADCggICAAAAA==.',
Su='Supay:BAAANQADCgUIBQAAAA==.',
Sw='Swinginsista:BAAANQAECgQIBQAAAA==.',
Ta='Talicso:BAAANQAECgQIBQAAAA==.Talos:BAAANQADCgcIDQABNQAECgQIBQABAAAAAA==.Tarkinal:BAAANQAECgQIBAAAAA==.',
Te='Teezee:BAAANQAECgEIAQAAAA==.Teitterdrud:BAAANQADCggICAAAAA==.Telira:BAAANQADCggIDwAAAA==.Tenderhoof:BAAANQAECgYICQAAAA==.',
Th='Thath:BAAANQADCgcIBwAAAA==.Thavus:BAAANQADCgYIBgAAAA==.Thearatwo:BAAANQADCgUIBQAAAA==.',
Ti='Tickz:BAAANQAECgIIAgAAAA==.Tinilia:BAAANQADCgQIBQAAAA==.Tirah:BAAANQAECgIIAgAAAA==.',
To='Toat:BAAANQADCgYIBgAAAA==.Toeran:BAAANQAECgEIAQAAAA==.Tokémon:BAAANQAECgEIAQAAAA==.Toxren:BAAANQAECgMIAwAAAA==.',
Tr='Traelin:BAAANQAECgQIBQAAAA==.Trickee:BAAANQADCggIDgABNQADCggIDgABAAAAAA==.',
Ts='Tskaha:BAAANQADCgYICAAAAA==.',
Ty='Tyria:BAAANQADCggIEgAAAA==.Tyruunas:BAAANQADCgMIAwAAAA==.',
Ur='Urizarah:BAAANQADCgYIBgAAAA==.',
Va='Vardamir:BAAANQAECgIIAgABNQAECgUIBwABAAAAAA==.Vashstampede:BAAANQADCgYICwAAAA==.',
Ve='Vei:BAAANQADCgMIAwABNQADCgIIAgABAAAAAA==.Velrik:BAAANQADCggIDAAAAA==.Venema:BAAANQADCgIIAgAAAA==.Venüs:BAAANQADCgcIBwAAAA==.Vezkin:BAAANQAECgQIBQAAAA==.',
Vi='Virtus:BAAANQADCggIDwAAAA==.Vizaimor:BAAANQADCgcIFgAAAA==.',
Vo='Vostok:BAAANQAECgQIBQAAAA==.',
We='Wealthyscaly:BAAANQADCgYIDQAAAA==.Werse:BAAANQAECgMIAwAAAA==.Wetloginyou:BAAANQADCggIDgAAAA==.',
Wh='Whodi:BAAANQADCgIIAgAAAA==.',
Wi='Witt:BAAANQADCgcICQAAAA==.',
Wo='Wolful:BAAANQAECgEIAQAAAA==.',
Wu='Wushoolay:BAAANQADCgcIBwAAAA==.',
Xn='Xnatem:BAAANQAECgEIAQAAAA==.',
Xo='Xoliver:BAAANQADCgYICQAAAA==.',
Ya='Yashiro:BAAANQAECgEIAQAAAA==.',
Ye='Yeraleth:BAAANQAECgQIBAAAAA==.',
Yo='Yorkj:BAAANQADCggIEAAAAA==.',
Za='Zalthorax:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Zatilion:BAAANQAECgIIAgAAAA==.Zavage:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.',
Ze='Zenru:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.',
Zi='Ziggashot:BAAANQAECgEIAQAAAA==.Zinsus:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Zo='Zongchi:BAAANQADCgcIBwAAAA==.',
Zu='Zurahahsha:BAAANQADCggIDgAAAA==.',
['Ðr']='Ðrow:BAAANQAECgQIBAAAAA==.',
['Óx']='Óxy:BAAANQAECgEIAQAAAA==.',
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
