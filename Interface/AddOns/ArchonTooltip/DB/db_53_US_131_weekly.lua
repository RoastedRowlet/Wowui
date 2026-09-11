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

local lookup = {'Unknown-Unknown','Warlock-Demonology',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Advîl:BAAANQAECgUIBQAAAA==.',
Ae='Aeryhnn:BAAANQADCgEIAQABNQADCgcIEwABAAAAAA==.',
Al='Alexandre:BAAANQAECgEIAQAAAA==.Allasia:BAAANQADCgYIBgAAAA==.Alton:BAAANQAECgcIDQAAAA==.',
Am='Amoonsia:BAAANQADCgUIBQAAAA==.',
An='Anfernyphere:BAAANQAECgcIBwABNQAECgMIBAABAAAAAA==.Ansuz:BAAANQAECgEIAQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgIIAgAAAA==.',
Aq='Aquafresh:BAAANQADCgUIBQAAAA==.',
Ar='Arisel:BAAANQADCggIEwAAAA==.Aristia:BAAANQADCggICAABNQAECgUICAABAAAAAA==.Arweni:BAAANQADCgcIEwAAAA==.',
At='Atheizt:BAAANQAECgYIDAAAAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Banedon:BAAANQADCgMIBQABNQAECgEIAQABAAAAAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Beetingu:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Belashar:BAAANQADCgUIBwAAAA==.Beytuha:BAAANQAECgEIAQAAAA==.',
Bi='Bighornygay:BAAANQAECggIBAAAAA==.',
Bl='Blacken:BAAANQADCggIEwAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQADCgcICwABNQAECgYIDQABAAAAAA==.Blakylightz:BAAANQAECgIIAgAAAA==.Blazen:BAAANQAECgcIEQAAAA==.Blinker:BAAANQAECgEIAQAAAA==.Bloodynuts:BAAANQAECggIEQABNQAECgIIAgABAAAAAA==.',
Bo='Bobbidyboo:BAAANQAECgcIEQAAAA==.Bonesclone:BAAANQADCgYIBgAAAA==.',
Br='Brewshido:BAAANQADCgEIAQAAAA==.Briareosx:BAAANQAECgIIAgAAAA==.Brovar:BAAANQAECgcIEQAAAA==.',
Bu='Bubbaa:BAAANQAECgYICAAAAA==.Buddydaelf:BAAANQAECgMIAwAAAA==.',
Bw='Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
Ce='Ceanaflowers:BAAANQADCgYIBgAAAA==.',
Ch='Chals:BAAANQAECgUICQAAAA==.Chia:BAAANQAECgEIAQABNQADCgMIAwABAAAAAA==.',
Co='Connor:BAAANQADCggICAAAAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Crosshair:BAAANQAECgIIAgAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAECgkJGAACAOwjAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.',
['Cê']='Cêlaçane:BAAANQADCgIIAgAAAA==.',
Da='Dacianwolf:BAAANQADCgYIDAAAAA==.Daravinius:BAAANQAECgEIAQAAAA==.Dare:BAAANQAECgIIAgAAAA==.Daveah:BAAANQADCggIEwAAAA==.',
De='Deathberry:BAAANQAECgEIAQAAAA==.Delphron:BAAANQADCgQIBgAAAA==.Demoncharge:BAAANQADCgYIDwAAAA==.Demonflayer:BAAANQADCgEIAQABNQADCgYIDwABAAAAAA==.Demonlust:BAAANQADCgIIAgABNQADCgYIDwABAAAAAA==.Denaeaa:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Depala:BAAANQADCgcIEAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAAANQAECgQICQAAAA==.',
Di='Dist:BAAANQADCgcIDQAAAA==.Divinestorm:BAAANQAECgEIAQAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Do='Dogbreathrlz:BAAANQABCgQIBgAAAA==.Dolomite:BAAANQABCgQIBwAAAA==.Dotexe:BAAANQABCgMIAwAAAA==.Dotsy:BAAANQAECgcIEQAAAA==.',
Dr='Drackarys:BAAANQADCgEIAQAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAAANQAECgYIDQAAAA==.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAAANQAECgIIAgAAAA==.Dravas:BAAANQADCgcIBwAAAA==.Drezzo:BAAANQADCgQICAAAAA==.Dryerbro:BAAANQABCgQIBAAAAA==.Drzark:BAAANQADCgYIDAAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgIIAgABAAAAAA==.',
Dw='Dwdog:BAAANQAECgEIAQAAAA==.',
['Dà']='Dàthguy:BAAANQAECgUICQAAAA==.',
['Dé']='Défault:BAAANQAECgYICwAAAA==.',
Ed='Edaras:BAAANQAECgEIAwAAAA==.',
El='Elennie:BAAANQADCgYIBgABNQADCgcIEAABAAAAAA==.',
Em='Emmi:BAAANQAECgEIAQAAAA==.',
En='Enyo:BAAANQAECgUIBQAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCgYIBgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggICAAAAA==.Feylen:BAAANQAECgIIAgAAAA==.',
Fi='Fido:BAAANQADCggIEwAAAA==.Fifthelement:BAAANQAECgEIAQAAAA==.Figgy:BAAANQAECgQIBAAAAA==.Fiorstrasza:BAAANQAECgEIAQAAAA==.Fistsofsmoke:BAAANQADCgEIAQAAAA==.',
Fj='Fjalgeirr:BAAANQAECgEIAQAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAAANQAECgEIAQAAAA==.',
Fr='Froot:BAAANQAECgIIAgAAAA==.Frßlizzard:BAAANQADCgMIAwAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAAANQAECgMIBQAAAA==.',
Ge='Gearsprocket:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.Geosmin:BAAANQAECgYIBgAAAA==.',
Gh='Ghue:BAAANQADCggIDQAAAA==.Ghòst:BAAANQADCgYIBgAAAA==.',
Gi='Gilalade:BAAANQAECgEIAQAAAA==.',
Go='Gonern:BAAANQAECgMIAwAAAA==.',
Gr='Gravestorm:BAAANQABCgYICQAAAA==.Grlfriend:BAAANQADCgQIBwAAAA==.Grodin:BAAANQADCgMIAwAAAA==.Grofiest:BAAANQADCgcIEgAAAA==.',
Gu='Gugg:BAAANQADCgIIAgABNQAECgYICQABAAAAAA==.Guggychan:BAAANQAECgYICQAAAA==.Gunsmoke:BAAANQADCgUICgAAAA==.',
Gw='Gwynbleidd:BAAANQAECgYICgAAAA==.',
Ha='Hadrian:BAAANQADCgMIAwAAAA==.Haohmaru:BAAANQAECgEIAQAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Hercgrim:BAAANQAECgQIBQAAAA==.Herger:BAAANQABCgUICQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyhunter:BAAANQADCgcIEgAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgEIAQAAAA==.',
Ir='Ironaxe:BAAANQAECgEIAQAAAA==.',
It='Itsademon:BAAANQADCgQIBAABNQADCgYIEgABAAAAAA==.',
Ja='Jaeksoolie:BAAANQAECgQIBwAAAA==.Jakyro:BAAANQAECgEIAQAAAA==.Javeech:BAAANQAECgQIBAAAAA==.Jaypark:BAAANQAECgYICQAAAA==.Jayse:BAAANQADCgMIAwAAAA==.',
Je='Jeren:BAAANQADCggIDAAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.',
Ju='Junghee:BAAANQAECgQIBQAAAA==.Juudaz:BAAANQAECgYIDQAAAA==.',
['Jï']='Jïnx:BAAANQAECgEIAQAAAA==.',
Ka='Kaalhvel:BAAANQADCgYIBgAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAAANQAECgEIAQAAAA==.Kapkywa:BAAANQADCggICAABNQAECgYIDAABAAAAAA==.Kasherquon:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Katsumyo:BAAANQADCgUICAAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Kilra:BAAANQAECgEIAQAAAA==.Kiyara:BAAANQAECgQIBAAAAA==.Kizaki:BAAANQAECgEIAQAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Kr='Krelliz:BAAANQAECgEIAQAAAA==.Krystar:BAAANQAECgIIAgAAAA==.',
Ku='Kungfuwho:BAAANQAECgUIBgAAAA==.',
La='Laysee:BAAANQADCgQIBgAAAA==.',
Le='Lenaea:BAAANQAECgcIDQAAAA==.',
Li='Liiege:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAAANQADCggIDQABNQAECgQIBgABAAAAAA==.',
Lo='Lobø:BAAANQAECgEIAQAAAA==.',
Lu='Luccyy:BAAANQADCgQIBwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunatyc:BAAANQAECgEIAQAAAA==.Luth:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Luthex:BAAANQAECgIIAgAAAA==.',
Ly='Lylacy:BAAANQAECgQIBAAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAAANQADCggIFAAAAA==.Manatee:BAAANQADCgYIBgAAAA==.Marqfourthre:BAAANQABCgUIBQAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meatlovers:BAAANQAECgEIAQAAAA==.Medb:BAAANQADCggIDQAAAA==.Melar:BAAANQAECgMIBQAAAA==.',
Mi='Minjae:BAAANQADCggIEwABNQAECgYICQABAAAAAA==.Misfirë:BAAANQAECgMIAwABNQAECgYICwABAAAAAA==.',
Mo='Mogwaí:BAAANQADCgcIDwAAAA==.Moondemon:BAAANQADCgUICwAAAA==.Morrìgan:BAAANQADCgYIDAAAAA==.Morvane:BAAANQADCgMIAwABNQAECgcIDQABAAAAAA==.Movack:BAAANQAECgEIAQAAAA==.Mowri:BAAANQABCgQIBgAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAAANQAECgEIAQAAAA==.',
My='Mytho:BAAANQABCgQIBQAAAA==.',
['Mö']='Mörï:BAAANQADCgYIDwAAAA==.',
Na='Nas:BAAANQADCgYIBwAAAA==.Natalina:BAAANQADCgYIBgABNQADCgcIEAABAAAAAA==.',
Ne='Nerfhammer:BAAANQAECgcIEQAAAA==.Nessalove:BAAANQAECgcIEQAAAA==.Neutrino:BAAANQAECgQIBAAAAA==.',
Ni='Nicolbowlass:BAAANQAECgEIAQAAAA==.Nightomen:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQADCgcIDAABNQAECgIIAgABAAAAAA==.',
No='Noone:BAAANQAECgQIBAAAAA==.',
Nz='Nz:BAAANQADCggIDgAAAA==.',
Od='Oddeccentric:BAAANQAECgQIBAABNQAECgcICwABAAAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgUICQABAAAAAA==.Overshoot:BAAANQADCgUICgAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Panterion:BAAANQADCgUIBgABNQAECgEIAQABAAAAAA==.Papimonk:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Parvarti:BAAANQAECgEIAQAAAA==.Pathogenic:BAAANQAECgQIBQAAAA==.',
Pe='Persimmoñ:BAAANQADCgUICgAAAA==.',
Ph='Philliesteak:BAAANQABCgQIBQAAAA==.',
Po='Polkadott:BAAANQAECgIIAgAAAA==.',
Pr='Presidìum:BAAANQAECgUIBgAAAA==.Procbiscuit:BAAANQAECgQIBQAAAA==.Prost:BAAANQAECgEIAQAAAA==.',
Ps='Psylocke:BAAANQAECgEIAQAAAA==.',
Pu='Pugshammy:BAAANQADCgUICQAAAA==.',
Py='Pyroblast:BAAANQAECgIIAgAAAA==.',
Ra='Rahuwu:BAAANQADCgEIAQABNQAECgYICQABAAAAAA==.',
Re='Reladin:BAAANQAECgEIAQAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Renzr:BAAANQAECgQICAAAAA==.Retpally:BAAANQADCgMIAwAAAA==.',
Ro='Roag:BAAANQAECgEIAQAAAA==.Roley:BAAANQAECgQIBAAAAA==.Rowin:BAAANQAECgIIAgAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgEIAQABNQADCgcIEwABAAAAAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristrix:BAAANQAECgIIAgAAAA==.Sarnara:BAAANQAECgEIAQAAAA==.Satyria:BAAANQAECgQIBgAAAA==.',
Se='Secord:BAAANQAECgEIAQAAAA==.Sereniity:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Seriiez:BAAANQABCgQICAAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQADCgUICAAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Sharku:BAAANQAECgYIEQAAAA==.Shegothalf:BAAANQADCgcIDAAAAA==.',
Sk='Skibblé:BAAANQADCggIDwAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQADCgYIEgAAAA==.',
Sm='Smokeofsteel:BAAANQADCgcIEwAAAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
Ss='Sskdp:BAAANQADCgIIAgABNQADCgMIBQABAAAAAA==.',
St='Stabsmcshank:BAAANQAECgYICgAAAA==.Starbux:BAAANQAECgIIAwAAAA==.Steakx:BAAANQAECgMIBQAAAA==.Stormwulf:BAAANQAECgIIAgAAAA==.',
Su='Sunmae:BAAANQADCgcIEgABNQADCggIEwABAAAAAA==.Suriel:BAAANQADCgcIEwAAAA==.Suumcuique:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Sv='Svenya:BAAANQADCgEIAQAAAA==.',
Sy='Sygne:BAAANQADCgYICQAAAA==.',
Sz='Szell:BAAANQADCggIEwAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwAAAA==.Tassandie:BAAANQAECgEIAQAAAA==.Tayebeh:BAAANQADCgMIAwAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAECgYIDQABAAAAAA==.',
Ti='Tionie:BAAANQADCgcIDQAAAA==.',
To='Toiletnuker:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Tokyojoe:BAAANQAECgMIBAAAAA==.Totemtot:BAAANQAECgEIAQAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwAAAA==.Traelindra:BAAANQADCggIDwAAAA==.',
Ty='Tygrala:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Uf='Uffizzle:BAAANQAECgEIAQAAAA==.',
Ul='Ulf:BAAANQAECgcICQAAAA==.',
Un='Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAAANQAECgQIBgAAAA==.Varlamor:BAAANQAECgEIAQAAAA==.Varolokiir:BAAANQADCgEIAQABNQAECgYIDQABAAAAAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAAANQAECgEIAQAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgEIAQAAAA==.Vervane:BAAANQAECgEIAQAAAA==.',
Vg='Vgerr:BAAANQAECgEIAQAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.',
Vo='Vohu:BAAANQAECgEIAQAAAA==.Voidpower:BAAANQADCgYIDwAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQABCgQIAwAAAA==.',
Xe='Xent:BAAANQAECgYIBgAAAA==.',
Xt='Xten:BAAANQADCgcIEwAAAA==.',
Yo='Yoshinox:BAAANQAECgMIBAAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgIIAgAAAA==.Zenagdrina:BAAANQADCgcIEAAAAA==.Zenobiå:BAAANQAECgIIAgAAAA==.',
Zh='Zhaann:BAAANQADCgcIEwAAAA==.',
Zo='Zorach:BAAANQADCgYICQAAAA==.',
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
