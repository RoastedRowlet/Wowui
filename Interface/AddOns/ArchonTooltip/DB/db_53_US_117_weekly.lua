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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAAANQAECgcIEAAAAA==.',
Ad='Adielia:BAAANQADCggIFAAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgMIAwAAAA==.',
Ag='Agiermodinn:BAAANQADCgYIBgAAAA==.',
Ah='Ahnho:BAAANQADCgUIBQAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQADCgUIBgABNQAECgEIAQABAAAAAA==.Airflash:BAAANQAECggIEAAAAA==.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAAANQADCggIDwABNQAECggIDQABAAAAAA==.',
Al='Alexious:BAAANQAECgcIDQAAAA==.Aloonarn:BAAANQAECgQIBAAAAA==.Alopix:BAAANQADCgcIEQAAAA==.Alulla:BAAANQAECggIEAAAAA==.Alunira:BAAANQAECgMIBAAAAA==.',
Am='Amberrfrost:BAAANQADCgYICwAAAA==.Amize:BAAANQADCgYIBgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAAANQAECgIIAgAAAA==.Angrywar:BAAANQAECgEIAgAAAA==.Anharon:BAAANQADCgYIBwAAAA==.Ansatz:BAAANQAECgIIAQAAAA==.',
Ap='Apokalypto:BAAANQADCgYIBwAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Arthan:BAAANQADCggICAAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Astanis:BAAANQADCggIDgAAAA==.Asteriia:BAAANQADCggIFwAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Av='Averettara:BAAANQADCgYICQABNQAECgMIBQABAAAAAA==.',
Az='Azka:BAAANQAECgMIBQAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAAANQAECgEIAQAAAA==.Baelmon:BAAANQADCgcICwAAAA==.Baludis:BAAANQADCgMIAwAAAA==.Bamff:BAAANQAECgIIAgAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Bast:BAAANQAECggIDQAAAA==.Basthara:BAAANQADCggICAABNQAECggIDQABAAAAAA==.',
Be='Benif:BAAANQAFFAEIAQAAAA==.Bertorod:BAAANQAECgUIBwAAAA==.',
Bi='Bigbitehotdo:BAAANQAECgUICwAAAA==.Bighoney:BAAANQADCgQIBgAAAA==.Binkyfiasco:BAAANQADCggIDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodstoned:BAAANQADCgQIBAAAAA==.Blueboy:BAAANQAECgEIAQAAAA==.',
Bo='Bonewrath:BAAANQABCgIIAgAAAA==.',
Br='Breadscrumb:BAAANQADCgUIBQAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.',
Bu='Burblbiblr:BAAANQADCgQIBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQADCgIIAgAAAA==.',
Ca='Cambrier:BAAANQAECgYICwAAAA==.Cameraop:BAAANQAECgYICQAAAA==.Cardinal:BAAANQADCgQIBAAAAA==.Castbo:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Ce='Cellesstia:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Ch='Chalada:BAAANQADCgEIAQABNQAECggICQABAAAAAA==.Chalastorm:BAAANQADCgYIBwABNQAECggICQABAAAAAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatnoir:BAAANQAECgEIAQAAAA==.Chestock:BAAANQADCgYIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Co='Codith:BAAANQADCgUIBQAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.',
Cr='Crnogorac:BAAANQAECggIAQAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAECgcIDwABAAAAAA==.',
Da='Dadstonks:BAAANQABCgQIBgAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dankbo:BAAANQAFFAEIAQAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQABCgEIAQAAAA==.Despondent:BAAANQADCgEIAQAAAA==.Devildj:BAAANQADCgcIFAAAAA==.Dezadian:BAAANQADCgYIEAAAAA==.',
Di='Dimitrios:BAAANQADCgcIDAAAAA==.Disolve:BAAANQAECgEIAQAAAA==.Dixxonciderr:BAAANQAECggIEwAAAA==.',
Dm='Dmoe:BAAANQADCgYICwAAAA==.',
Do='Doji:BAAANQADCgEIAQAAAA==.',
Dq='Dqe:BAAANQADCgYIBgAAAA==.',
Du='Duplicate:BAAANQAECggIDwAAAA==.Dustdruid:BAAANQAFFAEIAQAAAA==.Dustlock:BAAANQABCgYIBgAAAA==.Dustmage:BAAANQADCggIEAAAAA==.',
Dw='Dwarr:BAAANQAECgIIAgAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBgAAAA==.',
Eg='Eggrolls:BAAANQAECgYIEAAAAA==.',
El='Ellcrys:BAAANQAECgUIBQAAAA==.Elletta:BAAANQADCgEIAQAAAA==.',
Eq='Eqo:BAAANQAECgcIDAAAAA==.',
Er='Erisian:BAAANQADCgQIBAAAAA==.Erkêios:BAAANQADCggIDgABNQAECgUICQABAAAAAA==.',
Es='Escherichia:BAAANQADCgIIAgAAAA==.Estheban:BAAANQAECgMIBAAAAA==.',
Fa='Face:BAAANQADCgQIBQAAAA==.Fairgrim:BAAANQADCggICgAAAA==.Falin:BAAANQAECgYICgAAAA==.Faqueueeight:BAAANQAECggIDwAAAA==.Fatsloth:BAAANQADCgYICgAAAA==.Fatébringer:BAAANQADCgYIDAABNQADCgUIBQABAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQADCgEIAQAAAA==.Felcookies:BAAANQADCggIFAAAAA==.',
Fi='Fimtastic:BAAANQADCggIFQAAAA==.Finasy:BAAANQAECgEIAgAAAA==.Finnicka:BAAANQADCgYIEgAAAA==.Fistymisty:BAAANQAECgMIAwAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.',
Fr='Frostya:BAAANQADCgEIAQAAAA==.',
Ga='Galeriel:BAAANQAFFAEIAQAAAA==.Garault:BAAANQAECgIIAgAAAA==.Gavered:BAAANQADCgMIAwAAAA==.',
Ge='Gekoni:BAAANQADCgYIBgAAAA==.Geotracker:BAAANQAECgIIAgAAAA==.',
Go='Goolgame:BAAANQAECgcIDQAAAA==.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcICAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAAANQADCgQIBAAAAA==.Gruldag:BAAANQAECggIEAAAAA==.Grullander:BAAANQAECgMIBAAAAA==.',
Gu='Guiguiie:BAAANQADCggIEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBAAAAA==.',
Ha='Hailey:BAEANQADCgcIBwABNQAFFAEIAQABAAAAAA==.Halter:BAAANQADCgMIAwAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Hazzurd:BAAANQADCggIFAAAAA==.',
He='Header:BAAANQAFFAIIAgAAAA==.Heersbeest:BAAANQABCgIIAgAAAA==.Helane:BAAANQADCgUIBQAAAA==.Hermionee:BAAANQAECgMIBAAAAA==.Hetu:BAAANQABCgMIAgAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAAANQAECgUICQAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAECggICQABAAAAAA==.Holykoi:BAAANQAECgQIBgAAAA==.',
Hr='Hroarr:BAAANQAECgUIBQAAAA==.',
Hu='Humancarnage:BAAANQADCgEIAQAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAAANQAECgEIAQAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgEIAQAAAA==.',
Ia='Iatros:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAAANQADCgYIBgAAAA==.',
Iv='Ivantis:BAAANQADCgUIDAAAAA==.Ivie:BAAANQADCgIIAgAAAA==.',
Ja='Jaholypriest:BAAANQAECgEIAQAAAA==.Janjor:BAAANQAECgIIAgAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAAANQAECgcICwAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQADCggIEwAAAA==.',
Jj='Jjdruid:BAAANQADCgUIBwAAAA==.',
Jo='Jollygreene:BAAANQADCgcIEgAAAA==.',
Jp='Jpgigademon:BAAANQADCgIIAgAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Ka='Kalivan:BAAANQADCgYIBwAAAA==.Karametra:BAAANQADCgIIAgAAAA==.Karlldun:BAAANQADCgUIBQAAAA==.Kasmir:BAAANQAECgQIBgAAAA==.',
Ke='Kevv:BAAANQAECgYICgAAAA==.',
Kh='Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgIIAgAAAA==.',
Ki='Killaarrow:BAAANQAECgQIBgAAAA==.',
Kl='Klay:BAAANQAECgEIAQAAAA==.',
Km='Kmarte:BAEANQAECgUIBgAAAA==.Kmartt:BAEANQADCggICAABNQAECgUIBgABAAAAAA==.',
Ko='Kosmicknight:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Kr='Kraggers:BAAANQAECgQIBAAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Kryesta:BAAANQAECgUICAAAAA==.',
Kw='Kwarr:BAAANQAECgcIDwAAAA==.',
La='Laganddecay:BAAANQABCgYIDgAAAA==.Lalii:BAAANQADCgMIBAAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.',
Le='Leasin:BAAANQAECgQIBgAAAA==.Lethendervis:BAAANQADCgEIAQAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAAANQAECgQIBQAAAA==.Lillynelazar:BAAANQAECgUIBQABNQAECgMIAwABAAAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgUICwABAAAAAA==.Linithara:BAAANQAECgYIEAAAAA==.Littlehoosie:BAAANQAECggIAQAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAEIAwABAAAAAA==.Loram:BAAANQADCgQIBAAAAA==.Lostgrip:BAAANQADCgYICAAAAA==.',
Lu='Lucthedk:BAAANQADCgUIBwAAAA==.Lukis:BAAANQADCgQIBAAAAA==.Lunitari:BAAANQADCggICQAAAA==.Lunkbeck:BAAANQAECgEIAQAAAA==.',
['Lø']='Lørd:BAAANQAECgYICwAAAA==.',
Ma='Madik:BAAANQADCgEIAQAAAA==.Magicmegan:BAAANQADCgMIAwAAAA==.Maladin:BAAANQADCgEIAQAAAA==.Malvean:BAAANQADCgUIBwAAAA==.Manasa:BAAANQADCgQIBgAAAA==.Marceline:BAAANQADCgcIDQAAAA==.Matresstains:BAAANQAECgMIAwAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgEIAQAAAA==.Melranis:BAAANQADCgYICgAAAA==.',
Mi='Miluk:BAAANQADCgYICAAAAA==.Misconduct:BAAANQAECgEIAQAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQADCgYIEQAAAA==.Moonmx:BAAANQADCgEIAQAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Murdamoose:BAAANQADCgEIAQAAAA==.Mustysponge:BAAANQADCgIIAgAAAA==.',
My='Mysteryx:BAAANQAECgQIBQAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Naniwa:BAAANQADCgEIAQAAAA==.Nazura:BAAANQADCgUIBQAAAA==.',
Ne='Nereza:BAAANQADCgYICwAAAA==.Nesquip:BAAANQADCgYIBgAAAA==.',
Ni='Nightforday:BAABNQAECoEXAAICAAgJrB9yCwDqAgACAAgJrB9yCwDqAgAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noktas:BAAANQADCgYICwAAAA==.Nominé:BAAANQADCgQIBAAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgEIAQAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQADCggICAAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQADCggIFQAAAA==.',
Pa='Paapineau:BAAANQADCggICAAAAA==.Packes:BAAANQAECgQIBgAAAA==.Pakkohruun:BAAANQAECgUICgAAAA==.Pallywack:BAAANQAECgIIAwAAAA==.Parthima:BAAANQAECgEIAQAAAA==.',
Pe='Pettigrew:BAAANQADCgIIAgAAAA==.',
Ph='Phantomclone:BAAANQADCggIDgAAAA==.Philomena:BAAANQADCgQIBAAAAA==.',
Pi='Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQAAAA==.Porkbuns:BAAANQAECgQIBAAAAA==.',
Pr='Precious:BAAANQADCgEIAgAAAA==.Priestymon:BAAANQADCgIIAgABNQAFFAEIAQABAAAAAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAAANQAECgcICwABNQAECgcIDwABAAAAAA==.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIIAgAAAA==.Quaesitor:BAAANQADCgYICgAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAECgcIDwABAAAAAA==.',
Ra='Raathya:BAAANQAECgIIAgAAAA==.Raeljin:BAAANQAECgMIAwAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQADCgYIDAAAAA==.Ratgamerlol:BAAANQAECgUICQAAAA==.Rayennagrom:BAAANQADCgcICAAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAAANQADCgcIDgAAAA==.Reneana:BAAANQADCgYICgAAAA==.Restbo:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.',
Rh='Rhianonn:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Ri='Richardluis:BAAANQADCggIEAAAAA==.Rinehardtt:BAAANQAECggIDAAAAA==.Riverstyxx:BAAANQADCgEIAQAAAA==.Rivër:BAAANQADCgQIBAAAAA==.',
Ro='Robbell:BAAANQAECgYICwAAAA==.Rokyman:BAAANQAECgIIAgAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Rootsie:BAAANQADCgYIDQAAAA==.Roselynn:BAAANQAECgQIBQAAAA==.Rouby:BAAANQADCgcIEgAAAA==.',
Ru='Ruerl:BAAANQAECgQIBQAAAA==.Runentug:BAAANQAECgcIDAAAAA==.Rustyspell:BAAANQADCgIIAgAAAA==.',
Sa='Sanlordriel:BAAANQADCgEIAQAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sassiberry:BAAANQADCgUICgAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Scrembiblion:BAAANQADCggIDwAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Sensjei:BAAANQADCgMIBAAAAA==.Separatist:BAAANQADCgMIAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQADCggICAAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAAANQAECgQICQAAAA==.Shãdøwzzxz:BAAANQADCgYICQAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQABAAAAAA==.Skädoosh:BAAANQADCgUIBQAAAA==.',
Sm='Smokeyhaze:BAAANQADCgQIBAAAAA==.Smokin:BAAANQADCggIDwAAAA==.Smores:BAAANQADCgYIBgAAAA==.',
So='Solomonk:BAAANQADCgQIBAAAAA==.Solomus:BAAANQADCggIDAAAAA==.Sonal:BAAANQAECgMIAwAAAA==.Soter:BAAANQADCgIIAgAAAA==.',
St='Stelltrain:BAAANQABCgIIAwAAAA==.Stormiee:BAAANQAECgQIBgABNQADCgIIAgABAAAAAA==.Stormroid:BAAANQADCgUIBgAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.',
Su='Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAAANQAECgQICAAAAA==.',
Sw='Swurves:BAAANQAECgEIAQAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
Ta='Taedrum:BAAANQADCgcIDgAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQADCgEIAQAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Taloning:BAAANQADCgYIBgABNQAECgUICgABAAAAAA==.Talonstryke:BAAANQAECgUICgAAAA==.',
Te='Tenseiga:BAAANQADCggIDgABNQAECggIDQABAAAAAA==.Tevers:BAAANQADCgEIAQAAAA==.',
Th='Thaalion:BAAANQADCggICAAAAA==.Thebigshot:BAAANQADCgYIBgAAAA==.Theenforcer:BAAANQAECgcIDwAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Thetzin:BAAANQADCgYIDAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAAANQAECgQIBAAAAA==.Thingtwø:BAAANQADCggICAAAAA==.Thistle:BAAANQADCgYIBgABNQADCgQIBAABAAAAAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titø:BAAANQADCgYIDQAAAA==.',
To='Tomorrow:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Totoo:BAAANQAECggICQAAAA==.',
Tr='Tralis:BAEANQADCggIDgAAAA==.Tranarra:BAAANQAECgMIBgAAAA==.Traylo:BAAANQAECgEIAQAAAA==.',
Tv='Tvak:BAAANQAECgUIBgAAAA==.',
Tw='Twopump:BAAANQAECgMIAwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgEIAQAAAA==.',
Um='Umbryx:BAAANQADCgIIAgAAAA==.',
Un='Unholly:BAAANQADCgQIBQAAAA==.',
Ur='Uroro:BAAANQAECgcICwABNQAECggIEAABAAAAAA==.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vainqueur:BAAANQAECgEIAQAAAA==.Valienni:BAAANQADCgYIDgAAAA==.Vanderius:BAAANQADCgMIAwAAAA==.Vandernum:BAAANQADCgUIBwAAAA==.Vandersius:BAAANQADCggICwAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Verymelon:BAAANQABCgUIBgABNQAECgYIDgABAAAAAA==.Vestele:BAAANQADCggICAAAAA==.',
Vg='Vgx:BAAANQAECgIIAgAAAA==.',
Vi='Viintage:BAAANQAECgEIAQAAAA==.Viridius:BAAANQADCgMIAwAAAA==.Vishouspayne:BAAANQADCgIIAQAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
['Vä']='Väelün:BAAANQAECgQIBAAAAA==.',
Wa='Wachoosh:BAAANQADCgYICwAAAA==.Waidmanns:BAAANQAECgYICgAAAA==.',
Wh='Whatsaggro:BAAANQAECgMIBQAAAA==.Whatyamean:BAAANQAECgEIAQAAAA==.Whomonk:BAAANQADCgYIBgAAAA==.',
Wi='Wickedchick:BAAANQADCgUICQAAAA==.Willowknight:BAAANQADCgYICgAAAA==.',
Wr='Wrongname:BAAANQAECgEIAQAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
['Xß']='Xß:BAAANQADCgIIAwAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEANQAECgQICAAAAA==.',
Yu='Yulian:BAAANQADCgcIDAAAAA==.',
Za='Zaartyn:BAAANQAECgQIBgAAAA==.Zaater:BAAANQAECgEIAQAAAA==.',
Ze='Zeebeth:BAAANQAECgUIBwAAAA==.Zefi:BAAANQADCgYICQAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zerokai:BAAANQADCgQIBAAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.',
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
