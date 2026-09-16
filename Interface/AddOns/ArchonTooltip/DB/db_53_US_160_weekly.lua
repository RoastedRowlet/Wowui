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

local lookup = {'Druid-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Warlock-Affliction','Priest-Holy','Monk-Mistweaver','DemonHunter-Havoc','DeathKnight-Unholy','Paladin-Retribution','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Mage-Arcane','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Adjust:BAAANQAECgIIAgABNQAFFAQIBgABAAsNAA==.',
Ae='Aegrisomnia:BAAANQABCgMIAwABNQAECgYICwACAAAAAA==.Aeropunk:BAAANQADCgIIAgAAAA==.Aerys:BAAANQAECgYICQAAAA==.Aerøs:BAAANQAECgMIAwAAAA==.',
Ag='Aggiz:BAAANQADCgYIBgABNQAECgYICwACAAAAAA==.',
Aj='Ajaxprime:BAAANQAECggIEQAAAA==.',
Ak='Akiojonës:BAAANQADCgYIBgAAAA==.',
Al='Alesîa:BAAANQADCgUIDgAAAA==.Alfabika:BAAANQAECgQIBAAAAA==.Alzim:BAAANQAECgcIEgAAAA==.',
An='Angry:BAAANQAECgEIAQAAAA==.Ankelbiter:BAAANQAECgQIBQAAAA==.Anûbis:BAAANQADCggIDQAAAA==.',
Ar='Aragos:BAAANQAECgQIBQAAAA==.Arcelon:BAAANQAECgEIAQAAAA==.Arwenatak:BAAANQAECgYICwAAAA==.',
As='Asmoon:BAAANQAFFAIIAgAAAA==.',
At='Athren:BAAANQADCggIHgAAAA==.Athrogate:BAAANQAECgQIBwAAAA==.',
Au='Auraloxious:BAAANQAECgEIAQAAAA==.',
Av='Avanorina:BAAANQAECgUIBQAAAA==.',
Ba='Baelzheron:BAAANQABCgEIAQAAAA==.Baksylyk:BAAANQADCgYICwABNQAECgMIBQACAAAAAA==.Ballador:BAAANQAECgMIAwAAAA==.Barakoshamma:BAAANQAECgYIDAAAAA==.Barazudar:BAAANQAECgQICwAAAA==.Baroke:BAAANQADCgYIBgAAAA==.Barragadin:BAAANQADCgUIBQABNQAECgYICQACAAAAAA==.Barreta:BAAANQAECgQICAAAAA==.',
Be='Beck:BAAANQAECgQICwAAAA==.Beefykin:BAAANQADCgcICQAAAA==.Bellámuerté:BAAANQAECgYICAAAAA==.Bemmy:BAAANQADCgQIBAABNQAECgYICwACAAAAAA==.',
Bi='Bigdrandyy:BAAANQAECgYIDAAAAA==.Biggspal:BAAANQADCgYIBgAAAA==.',
Bl='Blackbird:BAAANQAECgYICwAAAA==.Blackmage:BAAANQADCgYIBgAAAA==.Bloodlordzz:BAAANQAECgQIBQAAAA==.Bloodreina:BAAANQAECgYIDwAAAA==.',
Bo='Bob:BAAANQAECgIIAgAAAA==.Bockandcalls:BAAANQAECgYICgAAAA==.Bolbi:BAAANQAECgIIAwAAAA==.',
Br='Brahm:BAAANQADCggIEAABNQAECgUICQACAAAAAA==.Breadnbudda:BAAANQADCgYIEAAAAA==.Brogar:BAAANQADCgcIEQAAAA==.',
Bu='Buffknight:BAAANQADCggICAABNQAECgUICQACAAAAAA==.Bulkam:BAAANQAECgYICgAAAA==.Bulkazarr:BAAANQAECgYIDgAAAA==.',
Ca='Callabash:BAAANQAECgYIDAAAAA==.',
Ce='Celarena:BAAANQAECgQIBgAAAA==.Cermit:BAAANQADCgUIBQAAAA==.',
Ch='Chewie:BAAANQADCgUIBQAAAA==.Chilla:BAAANQADCgQIBAAAAA==.Chomrogg:BAAANQAECgYIBQAAAA==.Chopzzpala:BAAANQADCgYICAAAAA==.Choubelle:BAAANQADCgQIBAAAAA==.Chyp:BAAANQAECgQIBgAAAA==.Chzpriest:BAAANQAECgcIBwAAAA==.',
Ci='Cichorì:BAACNQAFFIEJAAMDAAQJNhbDBQCwAAAEAAIJOxvsCgC3AAADAAIJMhHDBQCwAAA1AAQKgRgAAwMACQknIVEEAMACAAMACQlgG1EEAMACAAQABgnzG9M/AM0BAAAA.Cipa:BAAANQADCgcIBwAAAA==.Circee:BAAANQADCgYIDwAAAA==.',
Co='Colmer:BAAANQADCgMIAwAAAA==.',
Cr='Creckko:BAAANQABCgQIBwAAAA==.Crockito:BAACNQAFFIEOAAIFAAUJ8SO5AAA2AgAFAAUJ8SO5AAA2AgA1AAQKgR4AAwUACQnPJhoAABAEAAUACQnPJhoAABAEAAYAAQlXDja3ADEAAAAA.',
Cy='Cyrusdavirus:BAAANQADCgUIBQAAAA==.',
Da='Dabu:BAAANQAECgQIBAAAAA==.Danto:BAAANQAECgEIAQABNQAECgUICQACAAAAAA==.Darc:BAAANQADCgcIBwAAAA==.Darktroll:BAAANQAECgcIDwAAAA==.',
De='Depoprovera:BAAANQAECgYIEwAAAA==.Deqz:BAAANQAECgUICQAAAA==.',
Di='Diezel:BAAANQAECgIIAgABNQAECgMIAwACAAAAAA==.Dilox:BAAANQADCgYIEgAAAA==.Dinosaur:BAAANQAECgcIEgAAAA==.Dirtydee:BAAANQAECgYICwAAAA==.Disaaya:BAAANQAECgUICwAAAA==.Divinecheeks:BAAANQAECgIIAwAAAA==.',
Do='Donto:BAAANQADCggICAABNQAECgUICQACAAAAAA==.Dontos:BAAANQAECgEIAQABNQAECgUICQACAAAAAA==.Doodlebug:BAABNQAECoEcAAIHAAkJjBhCEQCzAgAHAAkJjBhCEQCzAgAAAA==.Dotsntaxes:BAABNQAECoEaAAQEAAkJEhipJwBFAgAEAAgJARWpJwBFAgADAAUJwxA9HwBAAQAIAAEJQgsOGABHAAAAAA==.',
Dr='Dracom:BAAANQADCggIEAAAAA==.Dracuujin:BAAANQADCggICAABNQAFFAMIBQAJAEEbAA==.Dralioli:BAAANQAECgMIAwAAAA==.Dreanil:BAAANQAECgUIBQAAAA==.Droho:BAAANQAECgcIEQABNQAFFAUICwAFAGgXAA==.Drroog:BAAANQADCgQIBQABNQAECgEIAQACAAAAAA==.',
Du='Dumper:BAAANQAECgIIAgAAAA==.',
Dw='Dwarfsize:BAAANQADCggICAABNQAFFAQIBgABAAsNAA==.',
['Dâ']='Dârn:BAAANQAECgYIDwAAAA==.',
El='Eleweaver:BAAANQADCgcIDAAAAA==.Elissra:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Elvispræstly:BAAANQADCgYIBgAAAA==.',
En='Enoughtalk:BAAANQAECgMIBgAAAA==.',
Eo='Eostre:BAAANQAECgYICwAAAA==.',
Eu='Eupherine:BAAANQAECgQICwAAAA==.',
Ev='Evillarry:BAAANQADCgYIBgAAAA==.Evilpaladin:BAAANQAECgYIDgAAAA==.',
Ez='Ezluz:BAAANQAECgUIDQAAAA==.',
Fa='Facsimile:BAAANQAECgUICAAAAA==.',
Fe='Festers:BAAANQAECgQIBQAAAA==.',
Fi='Fingerwalk:BAAANQAECgUICQAAAA==.',
Fl='Flappi:BAAANQAECgYICgAAAA==.Flappii:BAAANQADCgEIAQAAAA==.Flaster:BAAANQADCgYIBgAAAA==.Fluffykat:BAAANQAECgQICwAAAA==.',
Fo='Fosho:BAACNQAFFIELAAIFAAUJaBftAQDLAQAFAAUJaBftAQDLAQA1AAQKgRkAAgUACQkGJB0GAIcDAAUACQkGJB0GAIcDAAAA.',
Fr='Franch:BAAANQAECgQIBQAAAA==.Frank:BAAANQADCgYICwABNQAECgMIAwACAAAAAA==.Fraud:BAAANQAECgMIAwABNQAECgYIDwACAAAAAA==.Froddy:BAAANQAECgMIAwAAAA==.Frylockk:BAAANQAECgcIEAAAAA==.',
Fu='Furrykane:BAEANQAECggICwAAAA==.Future:BAAANQAECgUICwAAAA==.',
Ga='Gaara:BAAANQAECgMIAwAAAA==.Gamepunisher:BAAANQAECgYIDgAAAA==.Gares:BAAANQAECgYICwAAAA==.',
Gi='Giorbs:BAAANQADCgYIBgAAAA==.',
Go='Goatgeek:BAAANQABCgEIAQABNQAECgMIAwACAAAAAA==.Goham:BAAANQAECgYICwAAAA==.Goobe:BAAANQADCgQIBAABNQAECgYICwACAAAAAA==.Goontotem:BAAANQAECgEIAQAAAA==.Gorro:BAAANQADCgYIBgAAAA==.',
Gr='Grogon:BAAANQADCggIFAAAAA==.Gromlo:BAAANQAECgYIDwAAAA==.Grulog:BAAANQAECgMIBAAAAA==.',
Gu='Gunny:BAAANQAECgYIDwAAAA==.',
['Gã']='Gã:BAAANQADCgUIBQAAAA==.',
Ha='Haeliman:BAAANQADCgYIBgAAAA==.Haileigh:BAAANQADCgcIEwAAAA==.Harleigh:BAAANQABCgMIAgAAAA==.Havöc:BAAANQAECgYIDQAAAA==.',
He='Herpenderper:BAAANQADCggIBwAAAA==.',
Hi='Hikawa:BAAANQAECgYIEgAAAA==.Hippocratic:BAAANQAECgYIBgAAAA==.',
Ho='Honortheox:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.',
Hu='Huntemall:BAAANQAECgMIBAAAAA==.',
Hy='Hysteriix:BAEBNQAECoEaAAIKAAkJ0CP1AACiAwAKAAkJ0CP1AACiAwAAAA==.',
Ic='Iceshards:BAAANQAECgUICQAAAA==.Icraptotems:BAAANQAECgEIAQAAAA==.',
Id='Idtrapthat:BAAANQADCgQICAAAAA==.',
Il='Illidankior:BAAANQAECgcIDwAAAA==.Illirothas:BAAANQADCgYIBgABNQAECgYICwACAAAAAA==.',
Im='Imen:BAAANQAECgQICAAAAA==.Imsassy:BAAANQADCggIEwAAAA==.',
In='Infectedbøb:BAAANQAECgQIBgAAAA==.Inmortuae:BAAANQADCggIFgABNQAECgYICwACAAAAAA==.',
Io='Iornbane:BAAANQAECgMIAwAAAA==.',
Ir='Irissela:BAAANQADCgYICAAAAA==.',
Iv='Ivalice:BAAANQAECgcICQAAAA==.',
Iz='Izüal:BAAANQADCgYICQABNQAECgMIBQACAAAAAA==.',
Ja='Jafbe:BAAANQAECgUIBQAAAA==.Jaghatai:BAAANQAECgIIAgAAAA==.Jammer:BAAANQADCgYIBgAAAA==.',
Ji='Jimcarrey:BAAANQADCgYICAABNQAECgEIAQACAAAAAA==.Jimmyc:BAAANQAECgEIAQAAAA==.Jimmysi:BAAANQAECgYIBgAAAA==.',
Jo='Joemauma:BAAANQAECgUICgAAAA==.',
Jp='Jpam:BAAANQAECgcIEwAAAA==.',
Ju='Jumbosize:BAACNQAFFIEGAAIBAAQJCw1CAgA7AQABAAQJCw1CAgA7AQA1AAQKgSEAAgEACQmPJX4AAMkDAAEACQmPJX4AAMkDAAAA.Jupîter:BAAANQAECgEIAQAAAA==.Justamuslim:BAAANQADCggICAABNQAECgYICgACAAAAAA==.',
Ka='Kaerlif:BAAANQADCgcIBwABNQAECgkJGAALAA4dAA==.Kaiyley:BAAANQAECgUIBQAAAA==.Kalastrian:BAAANQAECgMIBQAAAA==.Karateshock:BAAANQAECgQIBgAAAA==.Karlmarks:BAAANQABCggICAAAAA==.Kazuren:BAAANQAECgQICAAAAA==.',
Ke='Keano:BAAANQAECgMIAwAAAA==.Keeldemall:BAAANQADCgIIAgAAAA==.Kelinna:BAAANQAECgIIAwAAAA==.',
Kh='Khmelnitsky:BAAANQADCggICAAAAA==.',
Ki='Kirin:BAAANQAECgIIBAAAAA==.',
Kl='Klaye:BAAANQADCgYICQABNQAECgUICQACAAAAAA==.',
Ko='Kodabonk:BAAANQAECgYIDwAAAA==.Kodanorth:BAAANQADCgUICAABNQAECgYIDwACAAAAAA==.Korthos:BAAANQAECgQIBQAAAA==.Kotara:BAAANQADCggIDwAAAA==.',
Kr='Kraur:BAAANQAECgYICwAAAA==.',
['Kì']='Kìngpin:BAAANQAECgUICgAAAA==.',
La='Lammp:BAAANQAECgcIEgAAAA==.Lamppally:BAAANQADCgQIBAABNQAECgcIEgACAAAAAA==.Lampshade:BAAANQADCggICAABNQAECgcIEgACAAAAAA==.Laws:BAAANQAECggIDQAAAA==.Lazydragon:BAAANQAECgUIDQAAAA==.',
Li='Liaeda:BAAANQAECgUICgAAAA==.Lianshi:BAAANQADCgUIBQAAAA==.Linainverse:BAAANQAECgEIAQAAAA==.Lixie:BAAANQADCggICAAAAA==.',
Lo='Lolo:BAAANQADCggICAABNQAFFAUICwAFAGgXAA==.Loosie:BAAANQADCgEIAQAAAA==.Lost:BAAANQADCgUIBQABNQAECggIDQACAAAAAA==.Lovely:BAAANQAECgEIAQAAAA==.',
Lu='Luduhcris:BAAANQADCgYIEAAAAA==.Lugnuts:BAAANQAECgUIDAAAAA==.Lumiltiand:BAABNQAECoEbAAIMAAgJUyHeDQD1AgAMAAgJUyHeDQD1AgABNQAFFAEIAQACAAAAAA==.',
Lw='Lwaxana:BAAANQADCgMIAwAAAA==.',
Ma='Makloy:BAAANQABCgYICAAAAA==.Malgoros:BAAANQAECgQIBAABNQAECgUICAACAAAAAA==.Malgrendin:BAAANQAECgUIEAAAAA==.Malty:BAAANQAECgYIDwAAAA==.Malédictias:BAAANQADCgYIEAAAAA==.Manataurus:BAAANQADCgYIBgAAAA==.Manuall:BAAANQAECgIIAgAAAA==.Marbas:BAAANQAECgUIBQAAAA==.Maxidk:BAAANQAECgUIDAAAAA==.Maximage:BAAANQADCggICAABNQAECgUIDAACAAAAAA==.Maximonk:BAAANQADCgQIBgABNQAECgUIDAACAAAAAA==.Mazëkeen:BAAANQADCggICAAAAA==.',
Me='Medîvh:BAAANQADCgEIAQAAAA==.',
Mi='Midgemaisel:BAAANQADCggIGwAAAA==.Mik:BAAANQABCgMIAgABNQADCgEIAQACAAAAAA==.Mikhael:BAAANQADCgEIAQAAAA==.Mirado:BAAANQAECgYIDwAAAA==.Mirix:BAAANQADCgUIBQAAAA==.Mithridates:BAAANQAECgQIBQAAAA==.',
Mo='Molonlabe:BAAANQADCgUIBQAAAA==.Monix:BAAANQAECgcICwAAAA==.Monkragga:BAAANQAECgYICQAAAA==.Mooseleroy:BAAANQAECgMIBAAAAA==.Mortarien:BAAANQAECgcIBgAAAA==.Mozai:BAAANQADCgIIAgABNQAECggIGAANAMMfAA==.',
Mu='Mugged:BAAANQAECgQICAAAAA==.',
My='Myrtle:BAAANQAECgUICAAAAA==.',
['Má']='Másóchist:BAAANQAECgcIBwAAAA==.',
Ne='Necrophobic:BAAANQADCgQIBAAAAA==.',
Ni='Nice:BAAANQADCgYIDAAAAA==.Niwatori:BAAANQAECgQICwAAAA==.',
No='Noah:BAACNQAFFIEKAAMOAAUJ5hEkAABuAQAOAAQJIxEkAABuAQAPAAMJzQ2BCADcAAA1AAQKgRwAAw4ACQkJJW4AAJcDAA4ACQkJJW4AAJcDAA8AAgnJFJo6AIwAAAAA.Nol:BAAANQAECggICgABNQAFFAYICwAQAAIfAA==.Nolarz:BAACNQAFFIELAAIQAAYJAh8lAABZAgAQAAYJAh8lAABZAgA1AAQKgR4AAhAACQkeJowBAJoDABAACQkeJowBAJoDAAAA.',
Nu='Nukthom:BAAANQADCgcICQAAAA==.',
Ny='Nyneaves:BAAANQAECgUIDAAAAA==.Nyst:BAAANQAECgUIDQAAAA==.',
Ob='Objekt:BAAANQAECgUIBwAAAA==.',
Oh='Ohmenwah:BAAANQADCgUICQAAAA==.',
Oj='Ojplosion:BAAANQAECgcIEAAAAA==.',
Ol='Olga:BAAANQAECgEIAgAAAA==.',
Om='Omghunter:BAAANQADCgYIBgAAAA==.',
On='Onisprite:BAAANQAECgEIAQAAAA==.',
Or='Orchaos:BAAANQADCgUIBgAAAA==.Ordhah:BAAANQAECgMIBQAAAA==.',
Os='Osanna:BAAANQADCggIFQAAAA==.',
Pa='Paladout:BAAANQAECgYIDwAAAA==.Palletjack:BAAANQAECgYIDgAAAA==.Palli:BAAANQADCgUIDQAAAA==.Paona:BAAANQAECgUICgAAAA==.Papafloppa:BAAANQADCgIIAgAAAA==.Paulioo:BAAANQABCgIIAgAAAA==.',
Pe='Peraroll:BAAANQADCggICAAAAA==.',
Ph='Phenphen:BAABNQAECoEWAAMQAAkJMRWZDwBCAgAQAAgJwRSZDwBCAgARAAUJ2BJDIABbAQAAAA==.Physicyan:BAAANQAECgMIBAAAAA==.',
Pl='Planetdru:BAAANQAECgYIDQAAAA==.',
Po='Pogster:BAAANQADCgcIBwAAAA==.Pollyy:BAAANQAECgUIBQAAAA==.Popshampain:BAAANQAECgQIBgAAAA==.',
Ps='Psychonight:BAAANQAECggIEwAAAA==.',
Pu='Punchydabear:BAAANQAECgUIAQAAAA==.',
Ra='Raenlling:BAAANQAFFAEIAQAAAA==.Ratscum:BAEANQADCggIFwAAAA==.Rayssa:BAAANQAECgUICwAAAA==.',
Re='Redeker:BAAANQAECgQICAAAAA==.Rentahunter:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.Revax:BAAANQABCgUIBAABNQAECgYICwACAAAAAA==.Reyna:BAAANQADCgQIBAABNQADCggICAACAAAAAA==.',
Rh='Rholand:BAAANQADCgQIBQAAAA==.',
Ri='Ricopsu:BAAANQAECgYICQAAAA==.',
Rn='Rngnar:BAAANQADCgUIBQAAAA==.',
Ro='Rocklii:BAAANQADCggIDQAAAA==.Roguewolf:BAAANQAECgYIDgAAAA==.Rokdomaa:BAAANQAECgUIBQAAAA==.Roki:BAAANQAECgUICQAAAA==.Rolow:BAAANQAECgUICwAAAA==.Roony:BAACNQAFFIEKAAIBAAYJhRpTAAAiAgABAAYJhRpTAAAiAgA1AAQKgR0AAgEACQnVIngDAD8DAAEACQnVIngDAD8DAAAA.Roritai:BAAANQABCgQIBAABNQAECgMIBAACAAAAAA==.Rot:BAAANQAECgYIEAAAAA==.Royle:BAAANQABCgQIBgAAAA==.',
Ru='Runes:BAAANQAECgcIDQAAAA==.Runnerjay:BAAANQADCggIDwABNQAECgYIEwACAAAAAA==.Ruuf:BAAANQAECgYICAAAAA==.',
Ry='Rysxn:BAAANQAECgYICAAAAA==.Ryuujins:BAACNQAFFIEFAAIJAAMJQRteBwARAQAJAAMJQRteBwARAQA1AAQKgRkAAwkACQnpJKwGADkDAAkACQmeJKwGADkDABIABQm/JB8FAN8BAAAA.',
Sa='Sago:BAAANQAECgYICwAAAA==.Sandman:BAAANQAECgQIAwAAAA==.',
Sc='Scumball:BAEANQADCgYICwABNQADCggIFwACAAAAAA==.Scyon:BAABNQAECoEiAAITAAkJJx0NKADxAgATAAkJJx0NKADxAgAAAA==.',
Se='Selinie:BAAANQABCgcICwAAAA==.Senari:BAAANQAECgQICAAAAA==.Senbane:BAAANQADCggICQAAAA==.Sencia:BAAANQAECgEIAQAAAA==.',
Sh='Shadowblazer:BAAANQAECgcIDwAAAA==.Shalizar:BAAANQADCgUICAAAAA==.Shanda:BAAANQAECgcIEQAAAA==.Shanto:BAAANQAECgUICQAAAA==.Sheesh:BAAANQADCgcIDgAAAA==.Shesheshenn:BAAANQAECggIDQAAAA==.Shoumei:BAAANQAECgYIDwAAAA==.Shugz:BAAANQADCgMIAwABNQAECgYIDgACAAAAAA==.Shuken:BAAANQAECggIAQAAAA==.',
Si='Silfra:BAAANQAECgQICAAAAA==.Sinfull:BAAANQADCggICAAAAA==.',
Sk='Skolaid:BAABNQAECoEYAAMUAAkJJCAdBwBLAwAUAAkJJCAdBwBLAwANAAEJpR8AAAAAAAAAAA==.',
Sl='Slapparazzi:BAAANQADCgYIBQAAAA==.',
Sm='Smilingdev:BAAANQADCggIEAABNQAECgMIAwACAAAAAA==.Smoopoodoop:BAAANQAECgUIBQAAAA==.',
Sn='Snagglepuss:BAAANQADCggICAAAAA==.Sneakysin:BAAANQADCgQIBAAAAA==.',
So='Soulmend:BAAANQAECgQIBQAAAA==.Soulsproxy:BAAANQABCgQIBQAAAA==.',
Sp='Spaceman:BAAANQAECgUIBwAAAA==.',
Sq='Sqûïsh:BAAANQADCggICAAAAA==.',
St='Stabbz:BAAANQADCgUIBQAAAA==.Stevetson:BAAANQADCgcICQAAAA==.Stoops:BAAANQADCggIFgAAAA==.Stormdemon:BAAANQAECgMIAwAAAA==.Stormspellz:BAAANQAECgYIDAAAAA==.',
Su='Supay:BAAANQADCggIFAAAAA==.',
Sw='Swinginsista:BAAANQAECgYIDwAAAA==.',
Ta='Taldath:BAAANQADCggICQAAAA==.Talicso:BAAANQAECgcIEwAAAA==.Talos:BAAANQAECgQIBQABNQAECgYIDwACAAAAAA==.Talzinn:BAAANQADCgYIBgABNQAECgYIDwACAAAAAA==.Tardalian:BAAANQADCgIIAgAAAA==.Tarkinal:BAAANQAECgUIDQAAAA==.Taurito:BAAANQAECgQIBAAAAA==.',
Te='Teezee:BAAANQAECgYICgAAAA==.Teitterdrud:BAAANQAECgUICAAAAA==.Telira:BAAANQAECgQIBAAAAA==.Tenderhoof:BAABNQAECoEbAAMVAAkJDR4eCwAvAwAVAAkJDR4eCwAvAwABAAEJmAQUQwApAAAAAA==.',
Th='Thanatus:BAAANQADCgQIBAAAAA==.Thath:BAAANQADCggIFwAAAA==.Thavus:BAAANQADCgYIBgAAAA==.Thearatwo:BAAANQAECgUIBQAAAA==.Thunderclapz:BAAANQAECgUIBQAAAA==.Thunsibution:BAAANQADCggICQABNQAECgcIDwACAAAAAA==.',
Ti='Tickz:BAAANQAECgUICwAAAA==.Tinilia:BAAANQADCgQIBQAAAA==.Tirah:BAAANQAECgUICwAAAA==.',
To='Toat:BAAANQADCgYIBgAAAA==.Toeran:BAAANQAECgYICwAAAA==.Tokémon:BAAANQAECgQIBQAAAA==.Toxren:BAAANQAECgcIEAAAAA==.',
Tr='Traelin:BAABNQAECoEYAAIUAAkJXyJ7AwCLAwAUAAkJXyJ7AwCLAwAAAA==.Trickee:BAAANQAECgQIBQABNQAECgQIBQACAAAAAA==.',
Ts='Tskaha:BAAANQAECgEIAQAAAA==.',
Ty='Tyria:BAAANQAECgEIAQAAAA==.Tyruunas:BAAANQADCgMIAwAAAA==.',
Ug='Uggthok:BAAANQAECgIIAgAAAA==.',
Ur='Urizarah:BAAANQADCgYIDAAAAA==.',
Ut='Uthrid:BAAANQADCgYIBgAAAA==.',
Va='Vanadis:BAAANQADCgcICwAAAA==.Vardamir:BAAANQAECgcIDAABNQAECgcIEgACAAAAAA==.Vashstampede:BAAANQADCgYICwAAAA==.',
Ve='Vei:BAAANQADCgQICgABNQADCgIIAgACAAAAAA==.Velrik:BAAANQAECgIIAgAAAA==.Venema:BAAANQADCgIIAgAAAA==.Venüs:BAAANQAECgEIAQAAAA==.Vezkin:BAAANQAECgcIEwAAAA==.',
Vi='Vintagejeans:BAAANQAECgUIBQAAAA==.Virtus:BAAANQAECgUICAAAAA==.Vitrixz:BAAANQADCgQIBAAAAA==.Vizaimor:BAAANQAECgYIBQAAAA==.',
Vo='Voi:BAAANQABCgIIAwABNQAECgEIAQACAAAAAA==.Vostok:BAAANQAECgcIEAAAAA==.',
Vu='Vulcãnus:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.',
We='Wealthyscaly:BAAANQAECgEIAQAAAA==.Weedzzar:BAAANQADCgQIBAAAAA==.Werse:BAAANQAECgYIDwAAAA==.Wetloginyou:BAAANQAECgMIAwAAAA==.',
Wh='Whodi:BAAANQAECgUICAAAAA==.',
Wi='Witt:BAAANQAECgQIBQAAAA==.',
Wo='Woementality:BAAANQADCgMIAwAAAA==.Wolful:BAAANQAECgQICAAAAA==.',
Wr='Wrathoftitan:BAAANQADCgIIAgAAAA==.',
Wu='Wushoolay:BAAANQAECgMIBgAAAA==.',
Xn='Xnatem:BAAANQAECgQICAAAAA==.',
Xo='Xoliver:BAAANQADCgYICQAAAA==.',
Ya='Yashiro:BAAANQAECgQICAAAAA==.',
Ye='Yeraleth:BAAANQAECgYIDgAAAA==.',
Yo='Yorick:BAAANQADCggIDgAAAA==.Yorkj:BAAANQAECgQIBAAAAA==.',
Za='Zalthorax:BAAANQADCgEIAQABNQAECgYICwACAAAAAA==.Zatilion:BAAANQAECgYIDAAAAA==.Zavage:BAAANQADCgYICgAAAA==.',
Ze='Zenki:BAAANQADCgIIAgAAAA==.Zenrune:BAAANQAECgcICgAAAA==.',
Zi='Ziggashot:BAAANQAECgYICwAAAA==.Zinsus:BAAANQADCggIEwABNQAECgYICwACAAAAAA==.',
Zo='Zongchi:BAAANQAECgEIAQAAAA==.',
Zu='Zurahahsha:BAAANQAECgUICQAAAA==.',
['Ðr']='Ðrow:BAAANQAECgcIDwAAAA==.',
['Óx']='Óxy:BAAANQAECgUICgAAAA==.',
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
