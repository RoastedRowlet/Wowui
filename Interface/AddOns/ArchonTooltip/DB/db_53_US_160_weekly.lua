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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Druid-Restoration','DeathKnight-Unholy','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Mage-Arcane',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=53,date='2026-09-08',data={Ae='Aegrisomnia:BAAANQABCgMIAwABNQAECgQIBQABAAAAAA==.Aeropunk:BAAANQADCgIIAgAAAA==.Aerys:BAAANQAECgYICQAAAA==.Aerøs:BAAANQADCggICAAAAA==.',
Aj='Ajaxprime:BAAANQAECgUIBgAAAA==.',
Ak='Akiojonës:BAAANQADCgYIBgAAAA==.',
Al='Alesîa:BAAANQADCgUIDAAAAA==.Alzim:BAAANQAECgcIEQAAAA==.',
An='Angry:BAAANQADCggIDAAAAA==.Ankelbiter:BAAANQAECgEIAQAAAA==.Anûbis:BAAANQADCggIDQAAAA==.',
Ar='Aragos:BAAANQAECgEIAQAAAA==.Arcelon:BAAANQAECgEIAQAAAA==.Arwenatak:BAAANQAECgQIBQAAAA==.',
At='Athren:BAAANQADCggIFgAAAA==.Athrogate:BAAANQAECgMIAwAAAA==.',
Au='Auraloxious:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.',
Av='Avanorina:BAAANQAECgUIBQAAAA==.',
Ba='Baksylyk:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Ballador:BAAANQADCggIFQAAAA==.Barakoshamma:BAAANQAECgQIBgABNQAECgUICAABAAAAAA==.Barazudar:BAAANQAECgQIBwAAAA==.Baroke:BAAANQADCgYIBgAAAA==.Barreta:BAAANQAECgMIBAAAAA==.',
Be='Beck:BAAANQAECgQIBwAAAA==.Beefykin:BAAANQADCgcICQAAAA==.Bellámuerté:BAAANQAECgIIAgAAAA==.Bemmy:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
Bi='Bigdrandyy:BAAANQAECgYIBwAAAA==.Biggspal:BAAANQADCgYIBgAAAA==.',
Bl='Blackbird:BAAANQAECgQIBQAAAA==.Blackmage:BAAANQADCgYIBgAAAA==.Bloodlordzz:BAAANQAECgQIBQAAAA==.Bloodreina:BAAANQAECgQICQAAAA==.',
Bo='Bob:BAAANQADCggIFAAAAA==.Bockandcalls:BAAANQAECgQIBAAAAA==.Bolbi:BAAANQAECgIIAwAAAA==.',
Br='Brahm:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.Breadnbudda:BAAANQADCgYICQAAAA==.Brogar:BAAANQADCgcIDQAAAA==.',
Bu='Bulkam:BAAANQAECgYIBgAAAA==.Bulkazarr:BAAANQAECgQICAAAAA==.',
Ca='Callabash:BAAANQAECgQIBgAAAA==.',
Ce='Celarena:BAAANQAECgIIAgAAAA==.',
Ch='Chewie:BAAANQADCgUIBQAAAA==.Chilla:BAAANQADCgQIBAAAAA==.Chomrogg:BAAANQAECgEIAQAAAA==.Chopzzpala:BAAANQADCgYICAAAAA==.Choubelle:BAAANQADCgQIBAAAAA==.Chyp:BAAANQAECgQIBgAAAA==.Chzpriest:BAAANQAECgcIBwAAAA==.',
Ci='Cichorì:BAAANQAFFAMIBAAAAA==.Cipa:BAAANQADCgcIBwAAAA==.Circee:BAAANQADCgYIDQAAAA==.',
Co='Colmer:BAAANQADCgMIAwAAAA==.',
Cr='Creckko:BAAANQABCgQIBQAAAA==.Crockito:BAACNQAFFIEJAAICAAUJ3x9zAAAZAgACAAUJ3x9zAAAZAgA1AAQKgRsAAwIACQm3Jg8AABMEAAIACQm3Jg8AABMEAAMAAQlXDlOQADQAAAAA.',
Cy='Cyrusdavirus:BAAANQADCgUIBQAAAA==.',
Da='Dabu:BAAANQADCgIIAgAAAA==.Danto:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Darktroll:BAAANQAECgUICAAAAA==.',
De='Depoprovera:BAAANQAECgYIDAAAAA==.Deqz:BAAANQAECgQIBQAAAA==.',
Di='Diezel:BAAANQADCgcICwABNQAECgEIAQABAAAAAA==.Dilox:BAAANQADCgYIDAAAAA==.Dinosaur:BAAANQAECgcIDgAAAA==.Dirtydee:BAAANQAECgQIBQAAAA==.Disaaya:BAAANQAECgQIBgAAAA==.Divinecheeks:BAAANQAECgIIAgAAAA==.',
Do='Dontos:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Doodlebug:BAAANQAECggIEAAAAA==.Dotsntaxes:BAAANQAECggIEAAAAA==.',
Dr='Dracom:BAAANQADCgQIBwAAAA==.Dracuujin:BAAANQADCggICAABNQAFFAIIAgABAAAAAA==.Dralioli:BAAANQADCggIFQAAAA==.Dreanil:BAAANQADCgUIBQAAAA==.Droho:BAAANQAECgYICgABNQAFFAQIBgACAGMYAA==.Drroog:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.',
Du='Dumper:BAAANQAECgIIAgAAAA==.',
Dw='Dwarfsize:BAAANQADCggICAABNQAECgkJGQAEABwkAA==.',
['Dâ']='Dârn:BAAANQAECgYICQAAAA==.',
El='Eleweaver:BAAANQADCgcIDAAAAA==.Elissra:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Elvispræstly:BAAANQADCgYIBgAAAA==.',
En='Enoughtalk:BAAANQAECgMIAwAAAA==.',
Eo='Eostre:BAAANQAECgQIBQAAAA==.',
Eu='Eupherine:BAAANQAECgQIBwAAAA==.',
Ev='Evilpaladin:BAAANQAECgYICAAAAA==.',
Ez='Ezluz:BAAANQAECgQICAAAAA==.',
Fa='Facsimile:BAAANQAECgIIAwABNQAECgQIBAABAAAAAA==.',
Fe='Festers:BAAANQAECgMIAwAAAA==.',
Fi='Fingerwalk:BAAANQAECgQIBAAAAA==.',
Fl='Flappi:BAAANQAECgUIBQAAAA==.Flappii:BAAANQADCgEIAQAAAA==.Flaster:BAAANQADCgYIBgAAAA==.Fluffykat:BAAANQAECgQIBwAAAA==.',
Fo='Fosho:BAABNQAFFIEGAAICAAQJYxiTAQBtAQACAAQJYxiTAQBtAQAAAA==.',
Fr='Franch:BAAANQAECgEIAQAAAA==.Frank:BAAANQADCgYICwABNQADCgcIEAABAAAAAA==.Froddy:BAAANQADCggIFQAAAA==.Frylockk:BAAANQAECgUICQAAAA==.',
Fu='Furrykane:BAEANQAECgYIBQAAAA==.Future:BAAANQAECgQIBgAAAA==.',
Ga='Gamepunisher:BAAANQAECgUICAAAAA==.Gares:BAAANQAECgQIBQAAAA==.',
Gi='Giorbs:BAAANQADCgYIBgAAAA==.',
Go='Goham:BAAANQAECgQIBQAAAA==.Goobe:BAAANQABCgIIAgABNQAECgQIBQABAAAAAA==.Gorro:BAAANQADCgYIBgAAAA==.',
Gr='Grogon:BAAANQADCggIDAAAAA==.Gromlo:BAAANQAECgYICQAAAA==.Grulog:BAAANQAECgIIAgAAAA==.',
Gu='Gunny:BAAANQAECgYICQAAAA==.',
['Gã']='Gã:BAAANQADCgUIBQAAAA==.',
Ha='Haeliman:BAAANQABCgYICgAAAA==.Haileigh:BAAANQADCgYIDAAAAA==.Harleigh:BAAANQABCgMIAgAAAA==.Havöc:BAAANQAECgUIBwAAAA==.',
He='Herpenderper:BAAANQADCgQIBAAAAA==.',
Hi='Hikawa:BAAANQAECgUICAAAAA==.Hippocratic:BAAANQADCggIDQAAAA==.',
Ho='Honortheox:BAAANQADCgEIAQAAAA==.',
Hu='Huntemall:BAAANQAECgEIAQAAAA==.',
Hy='Hysteriix:BAEANQAECggICwAAAA==.',
Ic='Iceshards:BAAANQAECgQIBAAAAA==.Icraptotems:BAAANQAECgEIAQAAAA==.',
Il='Illidankior:BAAANQAECgcICAAAAA==.Illirothas:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Im='Imen:BAAANQAECgMIBAAAAA==.Imsassy:BAAANQADCggIDgAAAA==.',
In='Infectedbøb:BAAANQAECgIIAgAAAA==.Inmortuae:BAAANQADCggIDgABNQAECgQIBQABAAAAAA==.',
Io='Iornbane:BAAANQADCgcICwAAAA==.',
Ir='Irissela:BAAANQADCgYICAAAAA==.',
Iv='Ivalice:BAAANQAECgIIAgAAAA==.',
Iz='Izüal:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Ja='Jafbe:BAAANQADCgcICwAAAA==.Jaghatai:BAAANQAECgIIAgAAAA==.Jammer:BAAANQADCgYIBgAAAA==.',
Ji='Jimcarrey:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.Jimmyc:BAAANQAECgEIAQAAAA==.Jimmysi:BAAANQAECgUIBQAAAA==.',
Jo='Joemauma:BAAANQAECgQIBQAAAA==.',
Jp='Jpam:BAAANQAECgcIDAAAAA==.',
Ju='Jumbosize:BAABNQAECoEZAAIEAAkJHCTFAACcAwAEAAkJHCTFAACcAwAAAA==.Jupîter:BAAANQADCgEIAQAAAA==.Justamuslim:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
Ka='Kaerlif:BAAANQADCgcIBwABNQAECgcIDgABAAAAAA==.Kalastrian:BAAANQAECgIIAgAAAA==.Karateshock:BAAANQAECgQIBgAAAA==.Karlmarks:BAAANQABCgEIAQAAAA==.Kazuren:BAAANQAECgMIBAAAAA==.',
Ke='Keano:BAAANQADCgcIDgAAAA==.Keeldemall:BAAANQADCgIIAgAAAA==.Kelinna:BAAANQAECgEIAQAAAA==.',
Ki='Kirin:BAAANQAECgIIAgAAAA==.',
Kl='Klaye:BAAANQADCgYICAABNQAECgMIBAABAAAAAA==.',
Ko='Kodabonk:BAAANQAECgYICQAAAA==.Kodanorth:BAAANQADCgUICAABNQAECgYICQABAAAAAA==.Korthos:BAAANQAECgEIAQAAAA==.Kotara:BAAANQADCggIDwAAAA==.',
Kr='Kraur:BAAANQAECgQIBQAAAA==.',
['Kì']='Kìngpin:BAAANQAECgQIBQAAAA==.',
La='Lammp:BAAANQAECgYICwAAAA==.Lampshade:BAAANQADCggICAABNQAECgYICwABAAAAAA==.Laws:BAAANQAECggIBgAAAA==.Lazydragon:BAAANQAECgUICQAAAA==.',
Li='Liaeda:BAAANQAECgQIBQAAAA==.Lianshi:BAAANQADCgUIBQAAAA==.Linainverse:BAAANQAECgEIAQAAAA==.',
Lo='Loosie:BAAANQADCgEIAQAAAA==.Lost:BAAANQADCgUIBQABNQAECggIBgABAAAAAA==.Lovely:BAAANQADCggIDAAAAA==.',
Lu='Luduhcris:BAAANQADCgYICgAAAA==.Lugnuts:BAAANQAECgUICAAAAA==.Lumiltiand:BAABNQAECoEWAAIFAAgJHCF3CQAMAwAFAAgJHCF3CQAMAwAAAA==.',
Lw='Lwaxana:BAAANQABCgYICQAAAA==.',
Ma='Makloy:BAAANQABCgYICAAAAA==.Malgoros:BAAANQAECgQIBAAAAA==.Malgrendin:BAAANQAECgQICwAAAA==.Malty:BAAANQAECgYICQAAAA==.Malédictias:BAAANQADCgYIEAAAAA==.Manataurus:BAAANQADCgYIBgAAAA==.Manuall:BAAANQADCggIEwAAAA==.Marbas:BAAANQAECgIIAgAAAA==.Maxidk:BAAANQAECgQIBwAAAA==.Maximonk:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.Mazëkeen:BAAANQADCggICAAAAA==.',
Mi='Midgemaisel:BAAANQADCggIEwAAAA==.Mik:BAAANQABCgMIAgABNQADCgEIAQABAAAAAA==.Mikhael:BAAANQADCgEIAQAAAA==.Mirado:BAAANQAECgYICQAAAA==.Mirix:BAAANQADCgUIBQAAAA==.Mithridates:BAAANQAECgEIAQAAAA==.',
Mo='Molonlabe:BAAANQADCgUIBQAAAA==.Monix:BAAANQAECgMIAwAAAA==.Monkragga:BAAANQAECgQIBAAAAA==.Mooseleroy:BAAANQAECgEIAQAAAA==.Mortarien:BAAANQAECgcIAQAAAA==.Mozai:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.',
Mu='Mugged:BAAANQAECgMIBAAAAA==.',
My='Myrtle:BAAANQAECgQIBAAAAA==.',
['Má']='Másóchist:BAAANQADCggICgAAAA==.',
Ne='Necrophobic:BAAANQADCgQIBAAAAA==.',
Ni='Nice:BAAANQADCgYIBwAAAA==.Niwatori:BAAANQAECgQIBwAAAA==.',
No='Noah:BAABNQAECoEaAAMGAAkJCSUtAAC9AwAGAAkJCSUtAAC9AwAHAAIJyRQXLQCaAAAAAA==.Nol:BAAANQAECgEIAQABNQAECgkJGgAIAB4mAA==.Nolarz:BAABNQAECoEaAAIIAAkJHiaLAAC4AwAIAAkJHiaLAAC4AwAAAA==.',
Nu='Nukthom:BAAANQADCgcICQAAAA==.',
Ny='Nyneaves:BAAANQAECgQIBwAAAA==.Nyst:BAAANQAECgQICAAAAA==.',
Ob='Objekt:BAAANQAECgEIAgAAAA==.',
Oh='Ohmenwah:BAAANQADCgUICQAAAA==.',
Oj='Ojplosion:BAAANQAECgYICQAAAA==.',
Ol='Olga:BAAANQAECgEIAQAAAA==.',
Om='Omghunter:BAAANQADCgYIBgAAAA==.',
On='Onisprite:BAAANQADCggIDgAAAA==.',
Or='Orchaos:BAAANQADCgEIAQAAAA==.Ordhah:BAAANQAECgIIAgAAAA==.',
Os='Osanna:BAAANQADCggIDQAAAA==.',
Pa='Paladout:BAAANQAECgYICQAAAA==.Palletjack:BAAANQAECgUICAAAAA==.Palli:BAAANQADCgUIDQAAAA==.Paona:BAAANQAECgQIBQAAAA==.Papafloppa:BAAANQADCgIIAgAAAA==.Paulioo:BAAANQABCgIIAgAAAA==.',
Pe='Peraroll:BAAANQADCggICAAAAA==.',
Ph='Phenphen:BAAANQAECggIDQAAAA==.Physicyan:BAAANQAECgEIAQAAAA==.',
Pl='Planetdru:BAAANQAECgUIBwAAAA==.',
Po='Pogster:BAAANQADCgcIBwAAAA==.Popshampain:BAAANQAECgIIAgAAAA==.',
Ps='Psychonight:BAAANQAECgcIDAAAAA==.',
Ra='Ratscum:BAEANQADCggIDwAAAA==.Rayssa:BAAANQAECgQIBgAAAA==.',
Re='Redeker:BAAANQAECgMIBAAAAA==.Rentahunter:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Reyna:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.',
Rh='Rholand:BAAANQADCgQIBQAAAA==.',
Ri='Ricopsu:BAAANQAECgYICQAAAA==.',
Rn='Rngnar:BAAANQADCgUIBQAAAA==.',
Ro='Rocklii:BAAANQADCgYICwAAAA==.Roguewolf:BAAANQAECgUICAAAAA==.Rokdomaa:BAAANQADCgcIBwAAAA==.Roki:BAAANQAECgQIBAAAAA==.Rolow:BAAANQAECgQIBgAAAA==.Roony:BAABNQAECoEaAAIEAAkJ1SKaAQBbAwAEAAkJ1SKaAQBbAwAAAA==.Roritai:BAAANQABCgQIBAABNQAECgIIAgABAAAAAA==.Rot:BAAANQAECgYICgAAAA==.Royle:BAAANQABCgQIBgAAAA==.',
Ru='Runes:BAAANQAECgYIBgAAAA==.Runnerjay:BAAANQADCggIDwABNQAECgYIDAABAAAAAA==.Ruuf:BAAANQAECgIIAgAAAA==.',
Ry='Rysxn:BAAANQAECgEIAgAAAA==.Ryuujins:BAAANQAFFAIIAgAAAA==.',
Sa='Sago:BAAANQAECgQIBQAAAA==.',
Sc='Scumball:BAEANQADCgYIBgABNQADCggIDwABAAAAAA==.Scyon:BAABNQAECoEYAAIJAAkJDxoUIwDEAgAJAAkJDxoUIwDEAgAAAA==.',
Se='Selinie:BAAANQABCgYICgAAAA==.Senari:BAAANQAECgMIBAAAAA==.Senbane:BAAANQADCggICQAAAA==.Sencia:BAAANQAECgEIAQAAAA==.',
Sh='Shadowblazer:BAAANQAECgYICgAAAA==.Shalizar:BAAANQADCgUICAAAAA==.Shanda:BAAANQAECgcIEQAAAA==.Shanto:BAAANQAECgMIBAAAAA==.Sheesh:BAAANQADCgcIDgAAAA==.Shesheshenn:BAAANQAECggIBgAAAA==.Shoumei:BAAANQAECgYICQAAAA==.Shugz:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.',
Si='Silfra:BAAANQAECgQIBAAAAA==.Sinfull:BAAANQADCggICAAAAA==.',
Sk='Skolaid:BAAANQAECggIEQAAAA==.',
Sl='Slapparazzi:BAAANQADCgUIBQAAAA==.',
Sm='Smilingdev:BAAANQADCggIEAABNQAECgMIBQABAAAAAA==.Smoopoodoop:BAAANQADCggIEQAAAA==.',
So='Soulmend:BAAANQAECgEIAQAAAA==.Soulsproxy:BAAANQABCgQIBQAAAA==.',
Sp='Spaceman:BAAANQAECgIIAgAAAA==.',
Sq='Sqûïsh:BAAANQADCggICAAAAA==.',
St='Stabbz:BAAANQADCgUIBQAAAA==.Stevetson:BAAANQADCgcICQAAAA==.Stoops:BAAANQADCggIFQAAAA==.Stormdemon:BAAANQADCggIFQAAAA==.Stormspellz:BAAANQAECgYIBgAAAA==.',
Su='Supay:BAAANQADCgcIDAAAAA==.',
Sw='Swinginsista:BAAANQAECgUICgAAAA==.',
Ta='Talicso:BAAANQAECgcIDAAAAA==.Talos:BAAANQAECgMIAwABNQAECgQICQABAAAAAA==.Tarkinal:BAAANQAECgQICAAAAA==.',
Te='Teezee:BAAANQAECgMIBAAAAA==.Teitterdrud:BAAANQAECgUIBQAAAA==.Telira:BAAANQAECgQIBAAAAA==.Tenderhoof:BAAANQAECgcIEAAAAA==.',
Th='Thanatus:BAAANQADCgQIBAAAAA==.Thath:BAAANQADCggIDwAAAA==.Thavus:BAAANQADCgYIBgAAAA==.Thearatwo:BAAANQADCgUIBQAAAA==.Thunderclapz:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Thunsibution:BAAANQADCggICAABNQAECgcICAABAAAAAA==.',
Ti='Tickz:BAAANQAECgQIBgAAAA==.Tinilia:BAAANQADCgQIBQAAAA==.Tirah:BAAANQAECgQIBgAAAA==.',
To='Toat:BAAANQADCgYIBgAAAA==.Toeran:BAAANQAECgQIBQAAAA==.Tokémon:BAAANQAECgQIBQAAAA==.Toxren:BAAANQAECgYICQAAAA==.',
Tr='Traelin:BAAANQAECgcIDAAAAA==.Trickee:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Ts='Tskaha:BAAANQADCgcIDwAAAA==.',
Ty='Tyria:BAAANQADCggIGgAAAA==.Tyruunas:BAAANQADCgMIAwAAAA==.',
Ur='Urizarah:BAAANQADCgYIDAAAAA==.',
Va='Vanadis:BAAANQADCgQIBAAAAA==.Vardamir:BAAANQAECgMIBQABNQAECgcIDgABAAAAAA==.Vashstampede:BAAANQADCgYICwAAAA==.',
Ve='Vei:BAAANQADCgMIBgABNQADCgIIAgABAAAAAA==.Velrik:BAAANQADCggIFAAAAA==.Venema:BAAANQADCgIIAgAAAA==.Venüs:BAAANQADCgcIBwAAAA==.Vezkin:BAAANQAECgcIDAAAAA==.',
Vi='Virtus:BAAANQAECgUIBQAAAA==.Vizaimor:BAAANQAECgYIAgAAAA==.',
Vo='Voi:BAAANQABCgIIAwABNQADCgcIBwABAAAAAA==.Vostok:BAAANQAECgcIDAAAAA==.',
We='Wealthyscaly:BAAANQAECgEIAQAAAA==.Werse:BAAANQAECgYICQAAAA==.Wetloginyou:BAAANQADCggIFQAAAA==.',
Wh='Whodi:BAAANQAECgMIAwAAAA==.',
Wi='Witt:BAAANQAECgEIAQAAAA==.',
Wo='Wolful:BAAANQAECgMIBAAAAA==.',
Wr='Wrathoftitan:BAAANQADCgIIAgAAAA==.',
Wu='Wushoolay:BAAANQAECgEIAQAAAA==.',
Xn='Xnatem:BAAANQAECgMIBAAAAA==.',
Xo='Xoliver:BAAANQADCgYICQAAAA==.',
Ya='Yashiro:BAAANQAECgMIBAAAAA==.',
Ye='Yeraleth:BAAANQAECgQICAAAAA==.',
Yo='Yorick:BAAANQADCggICAAAAA==.Yorkj:BAAANQADCggIGAAAAA==.',
Za='Zalthorax:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Zatilion:BAAANQAECgUIBwAAAA==.Zavage:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Ze='Zenki:BAAANQADCgIIAgAAAA==.Zenrune:BAAANQAECgIIAgABNQAECgYIDwABAAAAAA==.',
Zi='Ziggashot:BAAANQAECgQIBQAAAA==.Zinsus:BAAANQADCggICQABNQAECgQIBQABAAAAAA==.',
Zo='Zongchi:BAAANQADCgcIBwAAAA==.',
Zu='Zurahahsha:BAAANQAECgQIBAAAAA==.',
['Ðr']='Ðrow:BAAANQAECgYICgAAAA==.',
['Óx']='Óxy:BAAANQAECgUIBwAAAA==.',
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
