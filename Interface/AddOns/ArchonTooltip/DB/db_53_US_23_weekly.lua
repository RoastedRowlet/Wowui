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
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaradh:BAAANQAECgUIBQAAAA==.Aaradk:BAAANQAECgEIAgABNQAECgUIBQABAAAAAA==.',
Ab='Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Acez:BAAANQAECggICAAAAA==.',
Ad='Addilynn:BAAANQADCgEIAQAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAAANQADCgcIDQAAAA==.',
Ae='Aelania:BAAANQADCgYIBgAAAA==.Aelunara:BAAANQAECgMIAwAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQADCgYIBgAAAA==.',
Ai='Ailric:BAAANQADCgcIDAAAAA==.',
Al='Alarakian:BAAANQADCgQIBAAAAA==.Alexei:BAAANQADCgYIBgAAAA==.Aliakin:BAAANQAECgIIAgAAAA==.Alistarburns:BAAANQAECgQIBAAAAA==.Alkhan:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Altos:BAAANQAECgUIBQAAAA==.',
Am='Amarxd:BAAANQAECgUICAAAAA==.Amdabear:BAAANQADCgcIDAAAAA==.',
An='Angerclaw:BAAANQADCggIDgAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.',
Ar='Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAAANQADCggIDAAAAA==.',
Au='Aurochi:BAAANQADCgMIAwAAAA==.',
Av='Avastin:BAAANQADCgUIBgAAAA==.',
Aw='Awni:BAAANQAECgIIAgAAAA==.',
Ba='Bahbahr:BAAANQADCgYIBgAAAA==.Baknow:BAAANQADCgEIAQAAAA==.Bangbangji:BAAANQADCgUIAwABNQAECgYICQABAAAAAA==.Bartholas:BAAANQADCgYICAAAAA==.Bazzoo:BAAANQAECgEIAQAAAA==.',
Be='Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAAANQAECgQIBAAAAA==.Benzos:BAAANQAECgcICAAAAA==.Bequin:BAAANQADCgcIBwAAAA==.Berrd:BAAANQAECgEIAQAAAA==.',
Bh='Bhangbhang:BAAANQAECgIIAgAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQADCgYIBgAAAA==.',
Bl='Bluerose:BAAANQADCgUIBQAAAA==.Blurry:BAAANQADCgcIDQAAAA==.',
Br='Bradyswife:BAAANQADCgYIBwAAAA==.Brisketboy:BAAANQADCgQIBAAAAA==.Bro:BAAANQADCgYICgAAAA==.Bronthos:BAAANQADCggICAAAAA==.',
Bu='Buffbutton:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.',
['Bï']='Bïllï:BAAANQAECgQIBAAAAA==.',
Ca='Caerisma:BAAANQADCggIDgAAAQ==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgQIBAAAAA==.Charbzenberg:BAAANQADCgYICgAAAA==.Charisma:BAAANQADCgMIAwABNQADCggIDgABAAAAAQ==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgQIBQAAAA==.',
Cl='Cloax:BAAANQAECgMIAwAAAA==.',
Co='Coinbrew:BAAANQADCgQIBAAAAA==.',
Cr='Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIDAAAAA==.Cryhavok:BAAANQAECgQIBAAAAA==.',
Cu='Cussack:BAAANQAECgMIBQAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgYICQABAAAAAA==.Daghar:BAAANQAECgEIAQAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQADCgcIBwAAAA==.Darkgol:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Davioon:BAAANQAECgEIAQAAAA==.Dayrb:BAAANQADCgUIBQAAAA==.',
De='Deadtalini:BAAANQAECgUICQAAAA==.Deckerdramon:BAAANQAECgEIAQAAAA==.Demomachin:BAAANQADCggIDgAAAA==.Deucalyon:BAAANQADCgcIBwAAAA==.Devours:BAAANQAECgcICwAAAA==.',
Di='Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAAANQAECgcIDAAAAA==.',
Do='Donmegah:BAAANQADCgYICgAAAA==.',
Dr='Dragoncito:BAAANQADCgMIAwAAAA==.Draki:BAAANQADCgYICgAAAA==.',
Du='Duggo:BAAANQAECgEIAQAAAA==.Dutanu:BAAANQAECgEIAQAAAA==.',
Ei='Eirrin:BAAANQADCgQIBAABNQAECgMIBgABAAAAAA==.',
El='Elariin:BAAANQADCgYICwAAAA==.Elendira:BAAANQADCgYIBgAAAA==.Elleredreaux:BAAANQADCggIDAAAAA==.',
En='Endomorphism:BAAANQADCggIDgABNQAECgYICgABAAAAAA==.',
Es='Estradiol:BAAANQADCgYIBgAAAA==.',
Ez='Ezmelora:BAAANQAECgEIAQAAAA==.',
Fa='Falconlaugh:BAAANQADCggIDAAAAA==.Fantasie:BAAANQADCgMIBAABNQAECgEIAQABAAAAAA==.Fatherclutch:BAAANQADCgQIBgAAAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAAANQAECgMIAwAAAA==.',
Fe='Felwoof:BAAANQADCggIEAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fl='Flarllek:BAAANQADCgQIBwAAAA==.Flexxed:BAAANQAECgYICAAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Fry:BAAANQAECgcIBwAAAA==.',
Fu='Furystrike:BAAANQADCggIDAABNQAECgcICwABAAAAAA==.',
Ga='Galenaa:BAAANQADCgUIBwAAAA==.Ganondrow:BAAANQADCggIDwAAAA==.',
Ge='Gemelo:BAAANQADCgYICgAAAA==.Geromul:BAAANQADCgQIBAAAAA==.Gerrexs:BAAANQADCgYIDAAAAA==.',
Gi='Gibayy:BAAANQAECgEIAQAAAA==.Gibsonex:BAAANQADCgYICQAAAA==.Gilliamm:BAAANQAECgQIBgAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Go='Golath:BAAANQAECgIIAgAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAAANQADCgYICwAAAA==.Gothbutta:BAAANQADCgQICAAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Graydeon:BAAANQADCgYIBgAAAA==.Gregorian:BAAANQAECgEIAQAAAA==.Gremliin:BAAANQAECgQICAAAAA==.Grigo:BAAANQAECgIIAgAAAA==.',
Ha='Haniesh:BAAANQADCggICAAAAA==.Havideeznuts:BAAANQADCgUIBQAAAA==.',
He='Healmeharder:BAAANQADCgEIAQAAAA==.Healthcare:BAAANQADCggIEQAAAA==.',
Ho='Holdor:BAAANQADCgEIAQAAAA==.Holynoodle:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Ic='Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQIBAAAAA==.Illyssa:BAAANQADCgIIAgAAAA==.',
Im='Imcooleddown:BAAANQAECgEIAQAAAA==.Imptricity:BAAANQADCgQIBAAAAA==.',
In='Intaria:BAAANQAECgUICAAAAA==.',
Is='Isomorphism:BAAANQADCgYIBgAAAA==.',
Ja='Jackbeef:BAAANQAECgQIBQAAAA==.Jadedhooves:BAAANQAECgEIAQAAAA==.Jaggedlilhun:BAAANQAECgIIAgAAAA==.Jagruk:BAAANQADCgIIAgAAAA==.Jareyk:BAAANQAECgEIAQAAAA==.Jarladorin:BAAANQADCgUIAwAAAA==.Jaxodk:BAAANQAECgUIDQAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jedai:BAAANQAECggIDAAAAA==.Jerrysix:BAAANQAECgMIBQAAAA==.',
Ju='Judadiah:BAAANQADCgQIBwAAAA==.Judo:BAAANQAECgMIBAAAAA==.Justbeginner:BAAANQADCgYICAAAAA==.',
Jy='Jyloti:BAAANQADCgYIBgAAAA==.',
['Jà']='Jàxx:BAAANQADCgcIDAAAAA==.',
['Jä']='Jäxx:BAAANQADCggICAAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Ka='Kalrotten:BAAANQADCgcICgAAAA==.Kancisa:BAAANQADCgQIBAAAAA==.Katkot:BAAANQAECgEIAQAAAA==.Kayro:BAAANQADCgUIBgAAAA==.',
Kh='Khagolith:BAAANQADCggIDgAAAA==.',
Ki='Kioria:BAAANQADCgYIBgAAAA==.Kirishino:BAAANQADCgcICAAAAA==.',
Kk='Kkodabear:BAAANQADCgYIBgAAAA==.',
Ko='Kobiter:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.Kobito:BAAANQAECgIIAwAAAA==.Koup:BAAANQAECgYICgAAAA==.Koupe:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Kr='Kranx:BAAANQADCgUIBQAAAA==.Krayzebeef:BAAANQAECgIIAgAAAA==.Kriss:BAAANQADCgUICAAAAA==.',
Ku='Kupe:BAAANQADCgUIBQABNQAECgYICgABAAAAAA==.',
Ky='Kyewanda:BAAANQADCgYICgAAAA==.Kyusakuu:BAAANQAECgIIAgAAAA==.',
La='Laanu:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.Lahey:BAAANQAECgEIAQAAAA==.Lakes:BAAANQAECgMIBAAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lathara:BAAANQADCgYICgAAAA==.Lavs:BAAANQADCgcIBwAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.',
Le='Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAAANQAECgQIBAAAAA==.Lexiah:BAAANQADCgYICwAAAA==.',
Lo='Loamathor:BAAANQADCgUIBQAAAA==.Lorilyn:BAAANQADCgcIBwAAAA==.Lorthag:BAAANQAECgEIAQAAAA==.Loverone:BAAANQADCgIIAgAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Lulbah:BAAANQADCgIIAgAAAA==.Lunareclips:BAAANQADCgIIAgAAAA==.Lunarus:BAAANQADCggIDgAAAA==.',
['Lì']='Lìfe:BAAANQAECgQIBAAAAA==.',
['Ló']='Lónnìe:BAAANQADCggIDgAAAA==.',
Ma='Maelona:BAAANQADCggIDgAAAA==.Magrumok:BAAANQADCgYIBgAAAA==.Magthars:BAAANQADCgMIBQAAAA==.Magtide:BAAANQADCgUIBQAAAA==.Malväryx:BAAANQADCgcIDAAAAA==.Manbearpig:BAAANQAECgYICQAAAA==.Manman:BAAANQADCggIDQAAAA==.Marshes:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Masshooter:BAAANQADCgIIAwAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQADCggIDQAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Melirraei:BAAANQADCgMIAwAAAA==.Melkiel:BAAANQAECgIIAwAAAA==.Mentalmidget:BAAANQAECgIIAgAAAA==.',
Mi='Miclovin:BAAANQAECgQIBAAAAA==.Microplastic:BAAANQAECgIIAgAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikoani:BAAANQAECgIIAgAAAA==.Mirumahn:BAAANQADCgIIAgAAAA==.Misocursed:BAAANQADCgUIBwAAAA==.Misoquick:BAAANQADCgYICQAAAA==.Missogyny:BAAANQAECgMIAwAAAA==.',
Mo='Moadeab:BAAANQADCgUIBwAAAA==.Mogando:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Mogrogarg:BAAANQAECgEIAgAAAA==.Mogrosham:BAAANQADCgYIBgAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgYICwABAAAAAA==.Mordin:BAAANQADCgYIBgAAAA==.Moribelar:BAAANQADCgUIBQAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Morventhas:BAAANQADCgIIAgAAAA==.Mosshead:BAAANQADCgYIBwAAAA==.Mousethyr:BAAANQAECgEIAQAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAAANQAECgEIAQAAAA==.',
My='Myboycleetus:BAAANQADCgYICAAAAA==.Mynon:BAAANQADCgIIAgAAAA==.',
Na='Nachothings:BAAANQAECgcIDQAAAA==.',
Ne='Necrokat:BAAANQADCgUIBQAAAA==.',
Ni='Nihility:BAAANQAECgUIBgAAAA==.Nirgand:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
No='Noodlestang:BAAANQAECgQIBQAAAA==.Nool:BAAANQADCgQIBAAAAA==.Norgand:BAAANQAECgQIBAAAAA==.Nosleep:BAAANQAECgQIBAAAAA==.Notdumb:BAAANQADCgMIAwAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQADCgUIBgAAAA==.Nyduss:BAAANQADCgIIAgAAAA==.Nymphs:BAAANQADCgEIAQAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgUIBwAAAA==.',
Oc='Ocopoko:BAAANQADCgcIBwAAAA==.',
On='Onibushi:BAAANQADCgMIAwAAAA==.',
Oo='Oof:BAAANQADCgYICwAAAA==.',
Op='Ophinias:BAAANQADCgUIBgAAAA==.Optimize:BAAANQAECgMIAwAAAA==.',
Or='Orastal:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oroki:BAAANQADCggIAgAAAA==.',
Pa='Pandalo:BAAANQADCgUICQAAAA==.Parasiite:BAAANQAECgEIAgAAAA==.',
Pe='Peepocute:BAAANQADCgQIBQAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQADCggICAAAAA==.Physiowar:BAAANQADCggIDwAAAA==.',
Pi='Pickledeath:BAAANQAECgIIAgAAAA==.Pizzapuff:BAAANQADCgYICwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAAANQAECgYICQAAAA==.',
Pu='Pugi:BAAANQADCgEIAQAAAA==.',
Qt='Qtyy:BAAANQADCgUIBQAAAA==.',
Ra='Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgEIAQAAAA==.Ragehound:BAAANQADCgEIAQAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ranzor:BAAANQAECgEIAQAAAA==.Rashis:BAAANQAECgEIAQAAAA==.Raveyn:BAAANQADCggIDgAAAA==.',
Re='Regino:BAAANQADCgcICAAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Rekita:BAAANQAECgEIAQAAAA==.Retispagheti:BAAANQADCggICAAAAA==.Retnuh:BAAANQADCggIDQAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQADCgEIAQAAAA==.',
Ro='Roderika:BAAANQADCgYICwABNQAECgUICAABAAAAAA==.Rogsicle:BAAANQAECgUICAAAAA==.Rolockrad:BAAANQADCggIDQAAAA==.Rord:BAAANQAECgEIAQAAAA==.Royjacked:BAAANQADCgMIBAAAAA==.',
Ru='Rubberr:BAAANQADCgIIAgAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQADCgcIBwAAAA==.Runicstrike:BAAANQAECgcICwAAAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sagalia:BAAANQADCgIIAgAAAA==.Sahra:BAAANQAECgQIBQAAAA==.Sanctustrike:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Saraphina:BAAANQADCgYICQAAAA==.',
Se='Sellandre:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Seronja:BAAANQADCggICAAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Sherfight:BAAANQAECgEIAQAAAA==.Shielddaddy:BAAANQADCgYICwAAAA==.Shiftyzegg:BAAANQAECgQIBgAAAA==.',
Si='Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Sj='Sjardags:BAAANQADCgIIAgAAAA==.',
Sk='Skinwalk:BAAANQADCgcIBwAAAA==.Skrai:BAAANQADCggIEAAAAA==.',
Sl='Sleew:BAAANQAECgMIAwAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.',
Sm='Smokintrees:BAAANQADCgIIAgAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.',
So='Soggypringle:BAAANQADCgMIBAAAAA==.Solnath:BAAANQAECgMIAwAAAA==.',
Sp='Specsdraco:BAAANQAECgUIBQAAAA==.Spewpuke:BAAANQAECgEIAQAAAA==.Spicytomato:BAAANQADCggIDgAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAAANQAECgQIBAAAAA==.Stgermain:BAAANQAECgQIBAAAAA==.Stormlotus:BAAANQADCgUIBgAAAA==.Strikeanywer:BAAANQADCgIIAgAAAA==.',
Su='Superstoned:BAAANQADCgIIAgAAAA==.Surudk:BAAANQADCgUIBgAAAA==.',
Sy='Sylrana:BAAANQADCgYIBgAAAA==.',
Ta='Taktikil:BAAANQADCgQICAAAAA==.Talrad:BAAANQAECgMIAwAAAA==.Tazerxface:BAAANQAECgUIBQAAAA==.',
Te='Tealgos:BAAANQAECgQIBAAAAA==.',
Th='Thaiddous:BAAANQADCggIDgAAAA==.Thanx:BAAANQADCgUIBgAAAA==.Thebeefchief:BAAANQAECgcIDAAAAA==.Thebigmon:BAAANQAECgIIAgAAAA==.Thedabara:BAAANQADCgMIAwAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgQIBAAAAA==.Thorxx:BAAANQADCgUIBQAAAA==.Thrudheals:BAAANQAECgQIBgAAAA==.Thugnastie:BAAANQAECgEIAQAAAA==.',
Ti='Tika:BAAANQADCgQIBAAAAA==.',
To='Toastyshamy:BAAANQADCgUICgAAAA==.Tofrenm:BAAANQADCggIDAAAAA==.Togashi:BAAANQAECgQIBQAAAA==.Topnacho:BAAANQADCgEIAQABNQAECgcIDQABAAAAAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAAANQADCgcIDAAAAA==.Totesschnook:BAAANQADCgMIAwAAAA==.',
Tr='Tripallie:BAAANQADCgQIBAAAAA==.Trishian:BAAANQADCgIIAgAAAA==.Trunkmuffin:BAAANQADCgMIAQAAAA==.',
Tu='Tuckermax:BAAANQADCgMIBAAAAA==.Tusk:BAAANQADCggIDgAAAA==.',
Ug='Uglyashell:BAAANQADCgQIBgAAAA==.',
Un='Unit:BAAANQAECgYIBQAAAA==.',
Uv='Uva:BAAANQADCgcIDAAAAA==.',
Va='Vaelith:BAAANQAECgIIAgAAAA==.Valendara:BAAANQAECgEIAQAAAA==.Valsorin:BAAANQADCggIDQAAAA==.Valtaea:BAAANQAECgUIBgAAAA==.',
Vi='Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQIBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQADCgYICgABAAAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Voreah:BAAANQADCgYIBgAAAA==.',
Wa='Wafflxs:BAAANQAECgYIDAAAAA==.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAAANQAECgIIAgAAAA==.',
We='Wellfookthat:BAAANQAECgMIBAAAAA==.Weolf:BAAANQABCgIIAQAAAA==.',
Wh='Whiteshadows:BAAANQADCgIIAwAAAA==.Whyvala:BAAANQADCgUIBwABNQABCgIIBAABAAAAAA==.',
Wo='Wolnney:BAAANQAECgQIBQAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
['Wâ']='Wâarseer:BAAANQADCgMIBQAAAA==.',
Xa='Xalatoes:BAAANQAECgcICgAAAA==.Xanathar:BAAANQADCgIIAgAAAA==.',
Xi='Xiaoyu:BAAANQAECgYICAAAAA==.',
Xr='Xraiz:BAAANQADCgYIBgAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAAANQAECgcICwAAAA==.Yourboyblue:BAAANQADCgYIBgAAAA==.',
Yv='Yverrius:BAAANQADCgMIAwAAAA==.',
Za='Zanydruid:BAAANQADCgQIBgAAAA==.Zanza:BAAANQADCgYICgAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zearyth:BAAANQADCgYIBgAAAA==.Zegg:BAAANQADCgYICwAAAA==.',
Zh='Zhamazu:BAAANQADCgMIAwAAAA==.Zhygår:BAAANQADCgIIAgAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.',
Zo='Zodin:BAAANQADCgMIBQABNQADCggIDgABAAAAAA==.Zombiez:BAAANQAECgUICAAAAA==.Zoryn:BAAANQADCgMIAwABNQABCgMIAwABAAAAAA==.',
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
