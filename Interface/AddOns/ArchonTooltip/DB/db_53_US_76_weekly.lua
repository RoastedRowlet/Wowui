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
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Aberaht:BAAANQAECgMIAwAAAA==.Absolution:BAAANQADCgcICwAAAA==.',
Ac='Ackianae:BAAANQADCgQIBQAAAA==.',
Ad='Adewey:BAAANQAECgEIAQAAAA==.',
Ae='Aenastian:BAAANQADCgUICgABNQAECgEIAQABAAAAAA==.',
Al='Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAAANQADCggICAAAAA==.Allus:BAAANQABCgEIAQAAAA==.Alphaomega:BAAANQADCgYICQAAAA==.',
An='Anarcy:BAAANQADCgQIAwAAAA==.Anastaysha:BAAANQABCgQIBAABNQADCgUIBQABAAAAAA==.',
As='Astrocakes:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
At='Athenä:BAAANQAECgcICwAAAA==.Atsuma:BAAANQADCgYIBgAAAA==.Atthel:BAAANQADCggIDgAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQADCgcIDQAAAA==.',
Ba='Baela:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.',
Be='Benjinana:BAAANQADCgYIBQAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Bountty:BAAANQADCgYIBgAAAA==.',
Bu='Bulleitrye:BAAANQADCgYIBgAAAA==.',
By='Byorn:BAAANQAECgEIAQAAAA==.',
Ca='Cairdamane:BAAANQAECgIIAgAAAA==.Calidrina:BAAANQAECgMIAwAAAA==.',
Ce='Celldrassil:BAAANQADCgYICgAAAA==.Cereel:BAAANQADCgYICAABNQAECgQIBAABAAAAAA==.',
Ch='Chardaney:BAAANQADCgUIBQAAAA==.',
Ci='Cii:BAAANQADCgcICgAAAA==.Ciruzita:BAAANQADCgIIAgAAAA==.',
Co='Colandros:BAAANQADCgEIAQAAAA==.Colara:BAAANQADCgcIDQAAAA==.Coldspace:BAAANQAECgIIAgAAAA==.',
Cr='Crassberry:BAAANQAFFAEIAQAAAA==.',
Cy='Cyndal:BAAANQABCgQIBAABNQAECgEIAQABAAAAAA==.Cyntu:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.',
Da='Dankothy:BAAANQADCgUICgAAAA==.Dantes:BAAANQADCgEIAQAAAA==.Darkryu:BAAANQADCgUICgAAAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQADCgYICgAAAA==.',
De='Deathforever:BAAANQADCgYICgAAAA==.Deaus:BAAANQADCgYICgAAAA==.Delrus:BAAANQAECgMIAwAAAA==.Demon:BAAANQADCgUIBQABNQAECgcIDQABAAAAAA==.Denzvic:BAAANQADCgYICwAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Disowneege:BAAANQADCgUICAABNQAECgcIDQABAAAAAA==.',
Do='Doodu:BAAANQADCgcIBwAAAA==.',
Dr='Dragnas:BAAANQAECgMIAwAAAA==.Drakeskid:BAAANQAECgQIBwAAAA==.Dramakiller:BAAANQADCgYICgAAAA==.Drcornbread:BAAANQADCgYIBQAAAA==.Drcornellia:BAAANQADCgEIAQABNQADCgYIBQABAAAAAA==.Drdreggs:BAAANQADCgYICwAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.',
El='Elastar:BAAANQAECgMIAwAAAA==.Ellimist:BAEANQAECggIDAAAAA==.Elycee:BAAANQAECgEIAQAAAA==.',
Er='Eraser:BAAANQAECgIIAgAAAA==.Erazar:BAAANQADCgYICwAAAA==.Erickk:BAAANQAECgQIBgAAAA==.Eristela:BAAANQADCgMIBAAAAA==.',
Es='Escanorlion:BAAANQADCgYICwAAAA==.Essense:BAAANQAECgMIAwAAAA==.',
Ex='Exodari:BAAANQAECgEIAQAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Fe='Fel:BAAANQAECgQIBQAAAA==.',
Fi='Fibitz:BAAANQAECgQIBAAAAA==.Findstewie:BAAANQABCgQIBgAAAA==.Fiofio:BAAANQAECgMIAwAAAA==.Fizban:BAAANQADCgcIDQAAAA==.',
Fl='Flik:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Fr='Frigidheart:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.',
Ga='Gadogear:BAAANQADCgcIDQAAAA==.Galabren:BAAANQADCgQIBQAAAA==.Garlik:BAAANQADCgQIBAAAAA==.',
Gf='Gfr:BAAANQADCgYIBgAAAA==.',
Go='Goatcheeze:BAAANQADCgYICwAAAA==.Gohlemsaurus:BAAANQABCgIIAgAAAA==.',
Gu='Gulen:BAAANQADCgYICwAAAA==.',
Gw='Gwennevier:BAAANQABCgMIAwAAAA==.',
Ha='Halsten:BAAANQADCgYIBgAAAA==.',
He='Hellenkeller:BAEANQADCgYIDAABNQAECgcIDQABAAAAAA==.',
Hi='Hitt:BAAANQADCgYIBgAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.',
Hr='Hroc:BAAANQADCggIDgAAAA==.',
Il='Illune:BAAANQADCgYICQABNQAECgEIAQABAAAAAA==.',
Im='Imleapingit:BAAANQADCggICAAAAA==.',
In='Intoodeep:BAAANQAECgQIBQAAAA==.',
Ir='Ir:BAAANQAECgQIBQAAAA==.',
Is='Isawarriorr:BAAANQAECgIIAgAAAA==.Ishdo:BAAANQADCggIDgAAAA==.',
Ja='Jakytreehorn:BAAANQAECgcICgAAAA==.',
Je='Jenevelle:BAAANQADCgYIBgAAAA==.Jessiel:BAAANQADCgYICgAAAA==.Jet:BAAANQAECgMIAwAAAA==.',
Ju='Julthaenia:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.',
Ka='Karash:BAAANQAECgEIAgAAAA==.Karnrae:BAAANQADCggIDAAAAA==.Karynos:BAAANQAECgIIAgAAAA==.Katwolf:BAAANQADCgcIDQAAAA==.Katyah:BAAANQADCgIIAQAAAA==.',
Ko='Konspiracy:BAAANQAECgMIAwAAAA==.',
Kr='Kraguva:BAAANQADCgEIAQAAAA==.Krataar:BAAANQAECgEIAQAAAA==.Krous:BAAANQAECgcIDAAAAA==.',
['Kä']='Kämpfer:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.',
La='Lafiel:BAAANQAECgMIAwAAAA==.Laurandre:BAAANQADCgYIBgAAAA==.',
Li='Liefic:BAAANQABCgQIBgAAAA==.Lilibeth:BAAANQADCgIIAgAAAA==.Lilstooge:BAAANQABCgMIAwABNQABCgQIBgABAAAAAA==.',
Lu='Luckykilla:BAAANQAECgIIAgAAAA==.Lucÿ:BAAANQAECgYICQAAAA==.Lune:BAAANQADCgMIAwAAAA==.Lurith:BAAANQAECgMIAwAAAA==.',
Ma='Marahh:BAAANQABCgIIAgAAAA==.Mattbolt:BAAANQADCgYIBgAAAA==.Mayu:BAAANQABCgIIBgAAAA==.Mazigos:BAAANQADCgYIBgAAAA==.',
Me='Meristem:BAAANQADCgYICgAAAA==.Merko:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
Mo='Moedorai:BAAANQAECgIIAgAAAA==.Mogma:BAAANQADCgUIBQAAAA==.Moonbounds:BAAANQAECgcICgAAAA==.Moondoggey:BAAANQADCgUIBQAAAA==.Mousechief:BAAANQADCgUICAAAAA==.Moxxzi:BAAANQADCgcICQAAAA==.',
Mu='Muhfookinbak:BAAANQADCggICAAAAA==.',
Na='Naksu:BAAANQADCgIIBAABNQADCgUIBQABAAAAAA==.Naksù:BAAANQADCgUIBQAAAA==.Naksü:BAAANQADCgYICAAAAA==.',
Ne='Neifeb:BAAANQADCgEIAQAAAA==.Nerfherder:BAAANQABCgQIBAAAAA==.',
Ni='Nights:BAAANQAECgIIAwABNQAECgcIDQABAAAAAA==.Ninh:BAAANQAECgQIBQAAAA==.Ninthgate:BAAANQADCgQIBAAAAA==.',
No='Nogood:BAAANQADCgQIBAAAAA==.Notsodemon:BAAANQAECgQIBAAAAA==.',
Ny='Nyorai:BAAANQABCgIIAQAAAA==.Nyxwing:BAAANQADCgQIBAAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAAANQAECgEIAQAAAA==.',
Ol='Olydwarf:BAAANQADCgYIBgAAAA==.',
On='Onebadmutha:BAAANQADCgIIAgAAAA==.Ontop:BAAANQAECgQIBQAAAA==.',
Or='Orb:BAAANQADCgcIDgAAAA==.Ortinks:BAAANQADCggICwAAAA==.',
Ow='Owneege:BAAANQAECgcIDQAAAA==.',
Pa='Pallinar:BAAANQADCgQICAAAAA==.Pasquale:BAAANQADCgUICQAAAA==.',
Pe='Pebbles:BAAANQAECgEIAQAAAA==.',
Pi='Picklericky:BAAANQADCgIIAgAAAA==.Pilgrimm:BAEANQAECgcIDQAAAA==.Pistola:BAAANQADCgUIBQAAAA==.',
Pl='Plaguerott:BAAANQAECgEIAQAAAA==.Plaguewind:BAAANQADCgEIAQAAAA==.',
Po='Polydh:BAAANQAECgEIAQAAAA==.Poobah:BAAANQADCgYICwAAAA==.Popsicles:BAAANQAECgEIAQAAAA==.Pouffant:BAAANQADCgYICwAAAA==.',
Pr='Praddagy:BAAANQADCgQIBAAAAA==.Pronoz:BAAANQADCggIAQAAAA==.',
Pu='Purpyl:BAAANQADCgYICwAAAA==.',
Pw='Pwnjitsu:BAAANQAECgMIAwAAAA==.',
Py='Pyrothermia:BAAANQAECgcIDAAAAA==.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAAANQAECgQIBQAAAA==.Razak:BAAANQAECgQIBQAAAA==.',
Rd='Rdnckromeo:BAAANQADCgIIAgAAAA==.',
Re='Redlock:BAAANQADCgYICgAAAA==.Redrum:BAAANQAECgMIBQAAAA==.Renarin:BAAANQAECgQIBQAAAA==.Renisa:BAAANQAECgIIAgAAAA==.Retman:BAAANQADCggIDgAAAA==.Revlyk:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.',
Rh='Rhoanna:BAAANQADCgQIBAAAAA==.Rhoupert:BAAANQADCgQIBAABNQADCgcIBgABAAAAAA==.',
Ro='Roccot:BAAANQAECgMIAwAAAA==.Rotjaw:BAAANQADCggICQAAAA==.',
Sa='Saintess:BAAANQABCgQIBgAAAA==.',
Sc='Scalycat:BAAANQAECgIIAgAAAA==.Scum:BAAANQADCgUIBQAAAA==.',
Se='Senaeda:BAAANQADCgQIBAAAAA==.Senate:BAAANQAECgIIAgAAAA==.',
Sh='Shadowbear:BAAANQADCgUICQAAAA==.Sherrilyn:BAAANQADCgIIAgAAAA==.',
Si='Singularity:BAAANQAECgEIAQAAAA==.',
Sk='Skelli:BAEANQAECgQIBQABNQAECggIDAABAAAAAA==.Skittlesdan:BAAANQAECgEIAQAAAA==.',
Sl='Slaykween:BAAANQADCgYICQAAAA==.',
Sm='Smallz:BAAANQADCgYIBgABNQADCgcIDQABAAAAAA==.',
Sn='Snooptrogg:BAAANQADCgUIBQAAAA==.',
Sp='Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Stonedragon:BAEANQAECgUIBwAAAA==.Stormrender:BAAANQADCgUIBQAAAA==.Stormriders:BAAANQADCgMIAgAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQABCgQIBAABNQAECgEIAQABAAAAAA==.',
Su='Sukonamí:BAAANQAECgEIAQAAAA==.Suzhou:BAAANQADCgYICwAAAA==.Suzoomies:BAAANQADCggIDwAAAA==.',
Sw='Swisscheese:BAAANQADCgcIDgAAAA==.',
Sy='Sycò:BAAANQAECgEIAwAAAA==.Syraxa:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.',
['Sú']='Súbzerø:BAAANQADCggIAwABNQAECgYICgABAAAAAA==.',
Ta='Taedish:BAAANQADCgQIBAAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.',
Te='Tenastin:BAAANQADCgIIAgAAAA==.Terragosa:BAAANQADCgYICgAAAA==.Tetchybono:BAAANQADCggIDgAAAA==.Tettra:BAAANQABCgEIAQABNQAECgEIAQABAAAAAA==.',
Th='Thirinis:BAAANQADCgIIAgAAAA==.Thope:BAAANQADCgYICgAAAA==.Thundergirl:BAAANQADCgMIAwAAAA==.',
Tr='Traesdyne:BAAANQADCgMIBAAAAA==.Trailwalkur:BAAANQADCgYIDAAAAA==.Trainar:BAAANQABCgQIBAAAAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQADCgYIDAAAAA==.Turim:BAAANQADCgMIAwAAAA==.',
Ty='Tyrlidd:BAAANQADCgYICgAAAA==.',
Un='Unlikelytale:BAAANQADCggICAAAAA==.',
Ur='Uricash:BAAANQAECgQIBgAAAA==.Urzual:BAAANQADCgEIAQAAAA==.',
Va='Vandreynna:BAAANQAECgEIAQAAAA==.',
Ve='Velveetah:BAAANQADCgEIAQABNQADCgYIBQABAAAAAA==.Verbrennen:BAAANQAECgIIAgAAAA==.Verita:BAAANQADCgYICwAAAA==.',
Vi='Viviann:BAAANQAECgMIAwAAAA==.',
Wa='Wayloren:BAAANQADCgEIAQAAAA==.',
Wi='Wickathy:BAAANQADCggIDQAAAA==.',
Wo='Worstdps:BAAANQAECgQIBAAAAA==.',
Wu='Wuldorr:BAAANQAECgEIAQAAAA==.',
Wy='Wynnifred:BAAANQADCggIDgAAAA==.',
Xa='Xaltheris:BAAANQADCgYICwAAAA==.',
Xe='Xethreal:BAAANQADCgYICgAAAA==.',
Xz='Xzara:BAAANQAECgEIAQAAAA==.',
Yv='Yvvee:BAAANQADCgYIBgAAAA==.',
Zo='Zonora:BAAANQAECgQIBAAAAA==.',
['Äz']='Äzrael:BAAANQADCggIDgAAAA==.',
['Çr']='Çréwüsæðèr:BAAANQADCgYICwAAAA==.',
['Ðì']='Ðìaßlo:BAAANQAECgYICgAAAA==.',
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
