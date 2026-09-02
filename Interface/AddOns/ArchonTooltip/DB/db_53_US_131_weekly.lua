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
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Advîl:BAAANQADCggICwAAAA==.',
Ae='Aeryhnn:BAAANQADCgEIAQABNQADCgcIDQABAAAAAA==.',
Al='Alexandre:BAAANQADCgcIDAAAAA==.Allasia:BAAANQADCgYIBgAAAA==.Alton:BAAANQAECgUIBgAAAA==.',
Am='Amoonsia:BAAANQADCgUIBQAAAA==.',
An='Ansuz:BAAANQADCgUIBQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.',
Ar='Arisel:BAAANQADCgYICwAAAA==.Arweni:BAAANQADCgYIDAAAAA==.',
At='Atheizt:BAAANQAECgQIBgAAAA==.',
Az='Azael:BAAANQADCgcICwAAAA==.',
Ba='Banedon:BAAANQADCgMIBAABNQAECgEIAQABAAAAAA==.',
Be='Beetingu:BAAANQADCgIIAgABNQADCggIDwABAAAAAA==.Belashar:BAAANQADCgUIBwAAAA==.Beytuha:BAAANQADCgcIDAAAAA==.',
Bl='Blacken:BAAANQADCgcICwAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQADCgcICwABNQAECgYIBwABAAAAAA==.Blakylightz:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.Blazen:BAAANQAECgYICgAAAA==.Bloodynuts:BAAANQAECgYICQABNQAECgIIAgABAAAAAA==.',
Bo='Bobbidyboo:BAAANQAECgYICgAAAA==.',
Br='Briareosx:BAAANQADCgEIAQAAAA==.Brovar:BAAANQAECgYICgAAAA==.',
Bu='Bubbaa:BAAANQAECgIIAgAAAA==.Buddydaelf:BAAANQADCggIDQAAAA==.',
Bw='Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ch='Chals:BAAANQAECgQIBAAAAA==.Chia:BAAANQADCgcIDAABNQADCgMIAwABAAAAAA==.',
Cr='Crosshair:BAAANQADCgQIAgAAAA==.',
['Cê']='Cêlaçane:BAAANQADCgIIAgAAAA==.',
Da='Dacianwolf:BAAANQADCgYIDAAAAA==.Daravinius:BAAANQADCggIDwAAAA==.Dare:BAAANQADCggIDwAAAA==.Daveah:BAAANQADCgYICwAAAA==.',
De='Deathberry:BAAANQAECgEIAQAAAA==.Delphron:BAAANQADCgQIBgAAAA==.Demoncharge:BAAANQADCgUICQAAAA==.Demonflayer:BAAANQADCgEIAQABNQADCgUICQABAAAAAA==.Demonlust:BAAANQADCgIIAgABNQADCgUICQABAAAAAA==.Denaeaa:BAAANQADCggICAABNQAECgUIBgABAAAAAA==.Depala:BAAANQADCgcICwAAAA==.Devistaysha:BAAANQAECgQIBAAAAA==.',
Di='Dist:BAAANQADCgUIBwAAAA==.Divinestorm:BAAANQAECgEIAQAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Do='Dogbreathrlz:BAAANQABCgIIBAAAAA==.Dotexe:BAAANQABCgMIAwAAAA==.Dotsy:BAAANQAECgYICgAAAA==.',
Dr='Drackarys:BAAANQADCgEIAQAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAAANQAECgYIBwAAAA==.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAAANQADCggICAAAAA==.Dryerbro:BAAANQABCgIIAgAAAA==.Drzark:BAAANQADCgYIBwAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgIIAgABAAAAAA==.',
Dw='Dwdog:BAAANQADCgYIBwAAAA==.',
['Dà']='Dàthguy:BAAANQAECgQIBAAAAA==.',
['Dé']='Défault:BAAANQAECgQIBQAAAA==.',
Ed='Edaras:BAAANQAECgEIAQAAAA==.',
Em='Emmi:BAAANQAECgEIAQAAAA==.',
En='Enyo:BAAANQADCggICgAAAA==.',
Er='Erad:BAAANQADCgYIBgAAAA==.',
Fe='Feylen:BAAANQAECgIIAgAAAA==.',
Fi='Fido:BAAANQADCgYICwAAAA==.Fifthelement:BAAANQADCgcIDAAAAA==.Figgy:BAAANQADCgYIBgAAAA==.Fiorstrasza:BAAANQADCgcIBwAAAA==.Fistsofsmoke:BAAANQADCgEIAQAAAA==.',
Fj='Fjalgeirr:BAAANQADCgcIDAAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAAANQAECgEIAQAAAA==.',
Fr='Froot:BAAANQAECgIIAgAAAA==.Frßlizzard:BAAANQADCgMIAwAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAAANQAECgEIAQAAAA==.',
Ge='Gearsprocket:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Geosmin:BAAANQADCgQIBAAAAA==.',
Gh='Ghue:BAAANQADCgUIBQAAAA==.',
Gi='Gilalade:BAAANQAECgEIAQAAAA==.',
Go='Gonern:BAAANQAECgEIAQAAAA==.',
Gr='Grlfriend:BAAANQADCgMIAwAAAA==.Grodin:BAAANQADCgMIAwAAAA==.Grofiest:BAAANQADCgcIDAAAAA==.',
Gu='Gugg:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Guggychan:BAAANQAECgMIAwAAAA==.Gunsmoke:BAAANQADCgUIBQAAAA==.',
Gw='Gwynbleidd:BAAANQAECgQIBAAAAA==.',
Ha='Hadrian:BAAANQADCgMIAwAAAA==.Haohmaru:BAAANQAECgEIAQAAAA==.',
He='Hellßoy:BAAANQADCgUIBwAAAA==.Hercgrim:BAAANQAECgEIAQAAAA==.Herger:BAAANQABCgQIBgAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQADCgYICwAAAA==.',
Hu='Huneyhunter:BAAANQADCgcIDAAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQADCgcICwAAAA==.',
Ir='Ironaxe:BAAANQADCgcIDAAAAA==.',
It='Itsademon:BAAANQADCgQIBAAAAA==.',
Ja='Jaeksoolie:BAAANQAECgMIAwAAAA==.Jakyro:BAAANQAECgEIAQAAAA==.Javeech:BAAANQADCgYICQAAAA==.Jaypark:BAAANQAECgQIBAAAAA==.',
Je='Jeren:BAAANQADCggIDAAAAA==.',
Ju='Junghee:BAAANQAECgEIAQAAAA==.Juudaz:BAAANQAECgUIBwAAAA==.',
['Jï']='Jïnx:BAAANQADCgcICAAAAA==.',
Ka='Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAAANQAECgEIAQAAAA==.Kasherquon:BAAANQADCgYIBgAAAA==.Katsumyo:BAAANQADCgUICAAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Kilra:BAAANQADCgcIDAAAAA==.Kiyara:BAAANQADCgcIBwAAAA==.Kizaki:BAAANQADCgYIDAAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Kr='Krelliz:BAAANQADCgYICAAAAA==.Krystar:BAAANQADCgQIAgAAAA==.',
Ku='Kungfuwho:BAAANQAECgEIAQAAAA==.',
La='Laysee:BAAANQADCgQIBgAAAA==.',
Le='Lenaea:BAAANQAECgUIBgAAAA==.',
Li='Liiege:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
Lo='Lobø:BAAANQADCgcIDAAAAA==.',
Lu='Luccyy:BAAANQADCgQIBwAAAA==.Lunatyc:BAAANQADCggICQAAAA==.Luthex:BAAANQADCgQIAgAAAA==.',
Ly='Lylacy:BAAANQADCgcIDAAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAAANQADCgYIDAAAAA==.Manatee:BAAANQADCgYIBgAAAA==.Marqfourthre:BAAANQABCgIIAgAAAA==.Maygwyn:BAAANQADCgQIAgAAAA==.',
Me='Meatlovers:BAAANQADCggIDAAAAA==.Medb:BAAANQADCgUIBQAAAA==.Melar:BAAANQAECgEIAQAAAA==.',
Mi='Minjae:BAAANQADCgcIDQABNQAECgMIAwABAAAAAA==.Misfirë:BAAANQADCgUIBwABNQAECgQIBQABAAAAAA==.',
Mo='Mogwaí:BAAANQADCgUICAAAAA==.Moondemon:BAAANQADCgUIBwAAAA==.Morrìgan:BAAANQADCgYIBgAAAA==.Morvane:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Movack:BAAANQADCgcIBwAAAA==.',
Mu='Murderface:BAAANQAECgEIAQAAAA==.',
My='Mythunran:BAAANQADCggIDQAAAA==.',
['Mö']='Mörï:BAAANQADCgYICwAAAA==.',
Na='Nas:BAAANQADCgYIBgAAAA==.',
Ne='Nerfhammer:BAAANQAECgYICgAAAA==.Nessalove:BAAANQAECgYICgAAAA==.Neutrino:BAAANQADCgQIBAAAAA==.',
Ni='Nicolbowlass:BAAANQADCggIDgAAAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQADCgcIDAABNQAECgIIAgABAAAAAA==.',
Nz='Nz:BAAANQADCgYIBgAAAA==.',
Od='Oddeccentric:BAAANQAECgQIBAAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgQIBAABAAAAAA==.Overshoot:BAAANQADCgUICgAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Panterion:BAAANQADCgMIAwABNQADCgUICgABAAAAAA==.Parvarti:BAAANQADCgcIDAAAAA==.Pathogenic:BAAANQADCgcIDAAAAA==.',
Pe='Persimmoñ:BAAANQADCgUICgAAAA==.',
Ph='Philliesteak:BAAANQABCgIIAwAAAA==.',
Po='Polkadott:BAAANQADCggIDwAAAA==.',
Pr='Presidìum:BAAANQAECgEIAQAAAA==.Procbiscuit:BAAANQADCggIDAAAAA==.Prost:BAAANQADCgUIBQAAAA==.',
Ps='Psylocke:BAAANQADCgcICwAAAA==.',
Pu='Pugshammy:BAAANQADCgQIBAAAAA==.',
Py='Pyroblast:BAAANQAECgIIAgAAAA==.',
Ra='Rahuwu:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.',
Re='Reladin:BAAANQAECgEIAQAAAA==.Renzr:BAAANQAECgMIBAAAAA==.Retpally:BAAANQADCgMIAwAAAA==.',
Ro='Roag:BAAANQADCgQIBwAAAA==.Roley:BAAANQADCggIDgAAAA==.Rowin:BAAANQADCgYIBgAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgEIAQABNQADCgcIDQABAAAAAA==.Saristrix:BAAANQADCggICwAAAA==.Sarnara:BAAANQADCgcIDAAAAA==.Satyria:BAAANQAECgQIBgAAAA==.',
Se='Secord:BAAANQADCgcIDAAAAA==.Seriiez:BAAANQABCgMIBAAAAA==.',
Sh='Shamalicous:BAAANQADCgQIBQAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Sharku:BAAANQAECgQIBgAAAA==.Shegothalf:BAAANQADCgYIBgAAAA==.',
Sk='Skibblé:BAAANQADCgUIBwAAAA==.',
Sl='Slimthick:BAAANQADCgYIDAAAAA==.',
Sm='Smokeofsteel:BAAANQADCgcIDQAAAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
St='Stabsmcshank:BAAANQAECgQIBAAAAA==.Starbux:BAAANQAECgEIAQAAAA==.Steakx:BAAANQAECgEIAQAAAA==.Stormwulf:BAAANQAECgIIAgAAAA==.',
Su='Sunmae:BAAANQADCgYICwABNQADCgYICwABAAAAAA==.Suriel:BAAANQADCgcIDQAAAA==.',
Sv='Svenya:BAAANQADCgEIAQAAAA==.',
Sy='Sygne:BAAANQADCgMIAwAAAA==.',
Sz='Szell:BAAANQADCgYICwAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tassandie:BAAANQADCgUICgAAAA==.Tayebeh:BAAANQADCgMIAwAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAECgYIBwABAAAAAA==.',
Ti='Tionie:BAAANQADCgcIDQAAAA==.',
To='Toiletnuker:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Tokyojoe:BAAANQAECgEIAQAAAA==.Totemtot:BAAANQAECgEIAQAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwAAAA==.Traelindra:BAAANQADCggICQAAAA==.',
Ty='Tygrala:BAAANQADCgMIAwABNQADCgcIDAABAAAAAA==.',
Uf='Uffizzle:BAAANQADCggICAAAAA==.',
Ul='Ulf:BAAANQAECgIIAgAAAA==.',
Va='Valquirie:BAAANQAECgIIAgAAAA==.Varlamor:BAAANQADCgYIBgAAAA==.Varolokiir:BAAANQADCgEIAQABNQAECgYIBwABAAAAAA==.Vathraen:BAAANQADCgUIBAAAAA==.',
Ve='Velanistra:BAAANQADCggICQAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQADCgYICwAAAA==.Vervane:BAAANQADCgcIDAAAAA==.',
Vg='Vgerr:BAAANQADCgUICgAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAECgYICgABAAAAAA==.',
Vo='Voidpower:BAAANQADCgYICQAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
Wa='Waterlily:BAAANQADCgMIAwAAAA==.',
Xe='Xent:BAAANQADCgEIAQAAAA==.',
Xt='Xten:BAAANQADCgcIDQAAAA==.',
Yo='Yoshinox:BAAANQAECgEIAQAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQADCgQIAgAAAA==.Zenagdrina:BAAANQADCgYICgAAAA==.Zenobiå:BAAANQADCgUIBAAAAA==.',
Zh='Zhaann:BAAANQADCgcIDQAAAA==.',
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
