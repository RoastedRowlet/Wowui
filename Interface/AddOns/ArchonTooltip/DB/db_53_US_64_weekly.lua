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
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aamix:BAAANQAECgcICgAAAA==.Aarom:BAAANQAECggIDgAAAA==.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAAANQADCgcICgAAAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aerius:BAAANQADCgcICQAAAA==.',
Af='Affliclock:BAAANQAECgcICgAAAA==.',
Ai='Aingerfal:BAAANQADCgYICgAAAA==.',
Ak='Akasori:BAAANQAECgUICAAAAA==.',
Al='Alterboyy:BAAANQADCggIDwAAAA==.Alîsonshammy:BAAANQAECgcIBwAAAA==.',
Am='Ambersulfr:BAAANQADCggIDgAAAA==.Amrazz:BAAANQADCgcIBwAAAA==.Amzey:BAEANQAECgQIBgAAAA==.',
An='Anahata:BAAANQADCgEIAgAAAA==.Andromeda:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Anneaux:BAAANQADCgUIBQAAAA==.',
As='Ashaka:BAAANQADCgcIDQAAAA==.Astramis:BAAANQADCgYICwAAAA==.',
At='Atomicbarbie:BAAANQAECgQIBAABNQAECgcIBwABAAAAAA==.Atziri:BAAANQAECgMIAwAAAA==.',
Az='Azamia:BAAANQADCgYIBwABNQABCgIIAgABAAAAAA==.',
Ba='Backlash:BAAANQADCgEIAQAAAA==.Bam:BAAANQADCggICAABNQAECggIDQABAAAAAA==.Bamplify:BAAANQADCggICAABNQAECggIDQABAAAAAA==.Barrierbobo:BAAANQADCgYICwAAAA==.',
Be='Belmonk:BAAANQAECgEIAQAAAA==.Berdron:BAAANQAECgUICAAAAA==.',
Bl='Bladeliger:BAAANQAECgIIAgAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAAANQAECgcICQAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAAANQADCgcIDAAAAA==.Bonemair:BAAANQAECggIDgAAAA==.Boredasf:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCgQIBAAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQADCgYIEAABAAAAAA==.',
Bu='Bubblehooker:BAAANQAECgIIAgAAAA==.Buffnbeers:BAAANQADCgYICgABNQAECgcICwABAAAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQADCgUIAwAAAA==.',
Ca='Caldec:BAAANQAECggIDwAAAA==.',
Ch='Chainizard:BAAANQAECgIIAgAAAA==.Cheeno:BAAANQAECgQIBgAAAA==.Chihiro:BAAANQADCgcIDAAAAA==.Chillyfists:BAAANQADCgUIBQAAAA==.Chuffed:BAAANQABCgIIAgABNQADCgYIBgABAAAAAA==.',
Cl='Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMIAwABNQADCgYIEAABAAAAAA==.Computer:BAAANQAECgcIDQAAAA==.',
Cp='Cpteddie:BAAANQAECgYIDAABNQAFFAMIBAABAAAAAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQADCgUIBgABAAAAAA==.Crelam:BAAANQAECggIDgAAAA==.Cruentis:BAAANQAECgEIAQAAAA==.Crysuh:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Crysus:BAAANQAECgMIAwAAAA==.',
Da='Dabo:BAAANQAECgIIAgAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darwin:BAAANQADCgYICwAAAA==.Dasmoodhayn:BAAANQADCgYICQAAAA==.Davalanch:BAAANQAECgYICwAAAA==.Dazizejr:BAAANQAECgUIBgAAAA==.',
De='Deathxrage:BAAANQADCgcIDgAAAA==.Decor:BAAANQADCgYICQAAAA==.Denïed:BAAANQADCgQIBAAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Derpydk:BAAANQADCgYICwAAAA==.Dethkløk:BAAANQADCgUIBQAAAA==.',
Di='Dibstrum:BAAANQADCgcICQAAAA==.Digduug:BAAANQADCgYICQAAAA==.Dixqt:BAAANQAECgQIBAAAAA==.',
Do='Dogfight:BAAANQAECgcIDQAAAA==.Doilookfatou:BAAANQAECgEIAQAAAA==.',
Dr='Draxus:BAAANQADCgcICgAAAA==.Drshakaloo:BAAANQADCgcIDQAAAA==.',
Dy='Dyami:BAAANQADCggIDwAAAA==.Dynas:BAAANQADCgcIBwAAAA==.',
Ea='Earthcake:BAAANQAECgUIBgAAAA==.',
Ed='Eddielich:BAAANQAFFAMIBAAAAA==.',
Eg='Eggfumonk:BAAANQADCgYIEAAAAA==.',
El='Elasmon:BAAANQAECgEIAQAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elfpen:BAAANQADCgMIAwAAAA==.',
Er='Erragal:BAAANQADCgMIAwAAAA==.',
Fe='Felurián:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Fexli:BAAANQADCgMIAwAAAA==.',
Fi='Fireteeth:BAAANQADCgQIBAAAAA==.',
Fl='Flurtty:BAAANQADCgQIBAAAAA==.',
Fo='Folklore:BAAANQADCgYICwAAAA==.',
Fr='Frighrish:BAAANQADCggICAAAAA==.Frigomortis:BAAANQADCgUICgABNQADCgYICgABAAAAAA==.Frozown:BAAANQAECgQIBAAAAA==.Fruits:BAAANQADCgcIDAAAAA==.',
Fu='Furrylife:BAAANQADCgMIAwAAAA==.Fusebawx:BAAANQADCgUIBgAAAA==.Fuzzychin:BAAANQAECgEIAQAAAA==.',
['Fò']='Fòrlorn:BAAANQABCgEIAQAAAA==.',
Ga='Gardettos:BAAANQAECgIIAgAAAA==.Gargingoyles:BAAANQADCgIIAgAAAA==.',
Gh='Gharghael:BAAANQADCgEIAQAAAA==.',
Gi='Gip:BAAANQABCgIIBAAAAA==.',
Gl='Glimmer:BAAANQADCgQIBAAAAQ==.',
Gn='Gnxrr:BAAANQAECgQIBAAAAA==.',
Go='Gooncaine:BAAANQAECgMIBAAAAA==.Gorbstrasz:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQADCgcIDQAAAA==.',
Gr='Gregorz:BAAANQADCgMIAwAAAA==.Greyanna:BAAANQADCgYICwAAAA==.Gromthrall:BAAANQADCgYICwAAAA==.',
Gw='Gwynhwyfar:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Hb='Hbhealthen:BAAANQAECggIDQAAAA==.',
He='Hellhore:BAAANQADCgQICAAAAA==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAAANQAECgEIAQAAAA==.',
Ho='Holdenc:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Hoodz:BAAANQAECgIIAgAAAA==.Houseplant:BAAANQADCggIDAAAAA==.Howard:BAAANQADCgUICQAAAA==.',
Ib='Ibearprofen:BAAANQAECgEIAQAAAA==.',
Id='Idtrapdat:BAAANQAECgYICQAAAA==.',
Il='Ilse:BAAANQAECgIIAgAAAA==.',
Im='Imagined:BAAANQAECggIDgAAAA==.',
In='Indihunter:BAAANQADCgEIAQAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAAANQADCgcIDQAAAA==.Ivannalot:BAAANQADCgQIBAAAAA==.Ivracha:BAAANQADCgcIDQAAAA==.',
Ja='Jage:BAAANQADCgcICQAAAA==.Jarsham:BAAANQADCgYICgAAAA==.Jaràdan:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.',
Je='Jeff:BAAANQAECggIBAAAAA==.',
Jo='Joran:BAAANQADCgYIBwAAAA==.Jordie:BAAANQADCgIIAgAAAA==.',
Jw='Jwrs:BAAANQADCgcICAAAAA==.',
['Jï']='Jïbril:BAAANQAECgIIAgAAAA==.',
Ka='Kabbala:BAAANQAECgQIBAABNQAECggIDgABAAAAAA==.Kahlani:BAAANQAECgEIAQAAAA==.Kahlua:BAAANQADCgYICAAAAA==.Kailan:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Kalathios:BAAANQABCgIIAgABNQADCgYICgABAAAAAA==.Kaldro:BAAANQADCggIDwAAAA==.Kaly:BAAANQADCggIDwAAAA==.Kano:BAAANQABCgIIAgAAAA==.Kariana:BAAANQAECgIIAgAAAA==.Kathry:BAAANQADCgQIBAAAAA==.',
Ke='Keepdreaming:BAAANQADCggIDwAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keymebrah:BAAANQAECgcIDQAAAA==.',
Ko='Korda:BAAANQADCggICAAAAA==.Kosh:BAAANQADCgMIAwAAAA==.Koyra:BAAANQAECggIDgAAAA==.',
Ku='Kubwa:BAAANQABCgMIAwAAAA==.Kungfugimp:BAAANQADCgcIBwAAAA==.Kurral:BAAANQAECggIDgAAAA==.Kurstina:BAAANQADCgUIBQAAAA==.',
Ky='Kyramus:BAAANQADCgYICwAAAA==.',
La='Laconia:BAAANQAECgQIBAAAAA==.Lashstorm:BAAANQADCgcICwAAAA==.Lattsatnar:BAAANQADCggICAAAAA==.',
Le='Lebron:BAAANQADCgYIDAAAAA==.',
Li='Lilsnick:BAAANQADCgYIBwAAAA==.',
Ll='Llanthyl:BAAANQADCgYICwAAAA==.',
Lo='Lockbawx:BAAANQADCgUIAgABNQADCgUIBgABAAAAAA==.Lockntroll:BAAANQADCggIDwAAAA==.',
Lu='Lunafalia:BAAANQAECgIIAgAAAA==.Lurosa:BAAANQAECgcICgAAAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
Ma='Macready:BAAANQAECgUICAAAAA==.Magenin:BAAANQADCgYICgAAAA==.Maggotgut:BAAANQADCgQIBAAAAA==.Mairiachi:BAAANQADCgIIAgABNQAECggIDgABAAAAAA==.Maltessa:BAAANQADCgUICgABNQAECgIIAwABAAAAAA==.Marload:BAAANQAECgcICAAAAA==.',
Me='Melath:BAAANQADCgUIBQAAAA==.',
Mi='Midletons:BAAANQADCgYIBwAAAA==.Minikub:BAAANQADCgcICwAAAA==.',
Mn='Mnzn:BAAANQADCggIDwAAAA==.',
Mo='Moodroo:BAAANQADCgYIBwAAAA==.Moonanoke:BAAANQADCgYICAAAAA==.Moovoker:BAAANQAECgMIAwAAAA==.Morseques:BAAANQAECgIIAgAAAA==.Mortimer:BAAANQAECgIIAgAAAA==.Moz:BAAANQADCgMIAwAAAA==.',
Mu='Muggy:BAAANQAECgcIDQAAAA==.',
Mx='Mxkebfistin:BAAANQAECgYIDAAAAA==.Mxkebspinnin:BAAANQADCggICAABNQAECgYIDAABAAAAAA==.',
Na='Narama:BAAANQAECggIDQAAAA==.',
Ne='Nekka:BAAANQADCgQIBAAAAA==.Nethanos:BAAANQADCgMIAwAAAA==.Neverrmore:BAAANQADCgIIAgAAAA==.',
Ni='Ninæ:BAAANQAECgcICAAAAA==.Nitewïng:BAAANQADCgYICAABNQADCgQIBAABAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwAAAA==.Nohomoh:BAAANQADCgQIBAAAAA==.Nootau:BAAANQAECgMIBAAAAA==.',
Ny='Nyoz:BAAANQADCgQICAAAAA==.Nyxxadra:BAAANQAECgMIAwAAAA==.',
Om='Omegadeed:BAAANQAECgIIAgAAAA==.',
On='Onne:BAAANQADCgMIBgAAAA==.',
Or='Orcinus:BAAANQAECgQIBgAAAA==.Orcishfist:BAAANQADCggICAAAAA==.Orvar:BAAANQADCgcICQAAAA==.',
Pa='Pam:BAAANQAECggIDQAAAA==.',
Pe='Perfectdark:BAAANQAECggIDgAAAA==.Perse:BAAANQADCgcIDAAAAA==.',
Ph='Phathottie:BAAANQABCgEIAQABNQADCgYICgABAAAAAA==.Pheadas:BAAANQADCgUIBQAAAA==.',
Pi='Pieper:BAAANQAECgEIAQAAAA==.Pipa:BAAANQAECgUIBwAAAA==.Pippit:BAAANQAECgIIAgABNQAECgUIBwABAAAAAA==.',
Pl='Plokane:BAAANQAECgEIAQAAAA==.',
Po='Poacher:BAAANQADCgMIAwAAAA==.Poppapally:BAAANQADCgUIBQAAAA==.Porque:BAAANQADCgQIBQABNQADCgYIDAABAAAAAA==.Powar:BAAANQADCgUIAwAAAA==.',
Pr='Provence:BAAANQADCgIIAgAAAA==.',
Py='Pyreynna:BAAANQADCggIDgAAAA==.',
['Pè']='Pèppèr:BAAANQAECgIIAgAAAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Ralnorin:BAAANQADCgcICgAAAA==.Raschild:BAAANQADCgcICwAAAA==.',
Re='Realfrojd:BAAANQAECgEIAQAAAA==.Regginunchuk:BAAANQAECgMIAwAAAA==.Releronastus:BAAANQADCgUIBQAAAA==.Rextallion:BAAANQAECgQICAAAAA==.Reyson:BAAANQAECgIIAgAAAA==.',
Rh='Rhunon:BAAANQAECgYICQAAAA==.',
Ri='Rinthia:BAAANQAECgIIAwAAAA==.Ripyeet:BAAANQAECgQIBAAAAA==.',
Ro='Rol:BAAANQADCgQIBAAAAA==.Rolden:BAAANQADCgcICgAAAA==.',
Ru='Rukaji:BAAANQAECgEIAQAAAA==.',
['Rå']='Rågeadin:BAAANQADCgUIBQABNQADCgQIBQABAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAAANQADCggIDwAAAA==.Sarkang:BAAANQADCgYIEgAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Sc='Schutze:BAAANQAECgYIBgAAAA==.',
Sd='Sdadfeg:BAAANQAECgIIAgAAAA==.',
Se='Senco:BAAANQADCgYIBwAAAA==.',
Sh='Shabobado:BAAANQABCgEIAQAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shiipo:BAAANQADCgQIBAAAAA==.Shøck:BAAANQADCggICwAAAA==.',
Si='Siegfried:BAAANQADCggICQAAAA==.Silbanuz:BAAANQAECgEIAQAAAA==.Simplejakk:BAAANQADCgUIBQAAAA==.Sinterklaas:BAAANQADCgUIBQAAAA==.',
Sk='Skylee:BAAANQAECgEIAQAAAA==.',
Sl='Slark:BAAANQADCgcICQAAAA==.Slawth:BAAANQAECgEIAQAAAA==.',
Sm='Smexytimes:BAAANQADCgYIBgAAAA==.Smeyplus:BAAANQAECggIDgAAAA==.',
Sn='Snickeris:BAAANQADCgUICQABNQADCgYIBwABAAAAAA==.Snofawl:BAAANQAECgEIAQAAAA==.Snoranir:BAAANQADCgYIDAAAAA==.Snurchbasher:BAAANQADCggICAAAAA==.',
Sp='Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAAANQAECgIIAgAAAA==.',
Sq='Squidd:BAAANQADCgMIAwAAAA==.',
Su='Sureno:BAAANQAECgQIBAAAAA==.',
Sx='Sxyheålz:BAAANQAECgUICQAAAA==.',
Ta='Tanndari:BAAANQADCgQIBgAAAA==.Tartare:BAAANQADCgIIAgAAAA==.Tashaman:BAAANQAECgcICQAAAA==.',
Te='Teriheals:BAAANQADCgYICgAAAA==.',
Th='Thejorlane:BAAANQADCgQIBAAAAA==.Thiccholy:BAAANQAECgcICwAAAA==.Thiccshields:BAAANQADCgQIBAABNQAECgcICwABAAAAAA==.Thicctotemz:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Thogo:BAAANQAECgIIAgAAAA==.',
Ti='Tikaa:BAAANQADCgQICAAAAA==.',
To='Tokiya:BAAANQAECgcICwAAAA==.Tomerto:BAAANQAECgIIAgAAAA==.Toobeastly:BAAANQAECgQIBAAAAA==.Toonerdin:BAAANQADCgYICwAAAA==.',
Tr='Tril:BAAANQADCgYICwAAAA==.Trox:BAAANQADCgUICAAAAA==.Tryingmybest:BAAANQAECgcICwAAAA==.',
Tw='Twozero:BAAANQADCgIIAgAAAA==.',
Ty='Tyralen:BAAANQAECgIIAgAAAA==.Tyrandras:BAAANQADCggIDwABNQAECgIIAgABAAAAAA==.Tyrïon:BAAANQAECgYICgAAAA==.',
Un='Unlyfe:BAAANQADCgYICgAAAA==.',
Va='Vaero:BAAANQADCggIDwAAAA==.Vandenar:BAAANQADCgUICAAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.Velyssa:BAAANQADCgYICwAAAA==.',
Vi='Vibin:BAAANQAECgEIAgAAAA==.Vineeshewah:BAAANQADCgYICwAAAA==.',
Vo='Voidguy:BAAANQADCgYICgAAAA==.',
Vu='Vulsted:BAAANQADCgYICwAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
Wa='Wantedd:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Wh='Whatapal:BAAANQADCgUIBgAAAA==.',
Wi='Wilbo:BAAANQAECgQIBgABNQAECgcIDQABAAAAAA==.Wily:BAAANQADCgcIDQAAAA==.Wisperwing:BAAANQADCgcIDAAAAA==.',
Wo='Wolfdrudu:BAAANQADCgIIAgAAAA==.Worldfire:BAAANQAECgEIAQAAAA==.Wormadina:BAAANQADCgUIDgAAAA==.Wormszer:BAAANQADCgYICgAAAA==.',
Wy='Wynds:BAAANQAECggIDgAAAA==.',
Xi='Xi:BAAANQADCggIDwAAAA==.Xiaozhi:BAEANQADCgYICwAAAA==.',
Xz='Xzariana:BAAANQADCggIDQAAAA==.',
Yo='Yoirr:BAAANQADCgEIAQAAAA==.',
Yu='Yuff:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.',
['Yë']='Yëëter:BAAANQADCgQIBAAAAA==.',
Za='Zach:BAAANQADCgIIAgABNQADCgcICgABAAAAAA==.Zanori:BAAANQAECgEIAQAAAA==.Zansijo:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Zo='Zolajin:BAAANQADCgUIBQAAAA==.Zorriya:BAAANQAECggIDQAAAA==.Zoyn:BAAANQADCgYIBgAAAA==.',
Zy='Zygo:BAAANQADCgYICAAAAA==.',
['Ár']='Áries:BAAANQAECgMIBAAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Ðemonicßlaze:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
['Ýu']='Ýuno:BAAANQADCgQIBAAAAA==.',
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
