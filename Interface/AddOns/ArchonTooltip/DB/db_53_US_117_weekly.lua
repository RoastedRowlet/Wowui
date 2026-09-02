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
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Actionfigure:BAAANQAECgcICQAAAA==.',
Ad='Adielia:BAAANQADCgcIDAAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQADCggIDgAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Airflash:BAAANQAECgQIBgAAAA==.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAAANQADCgYIBwABNQAECgYIBgABAAAAAA==.',
Al='Alexious:BAAANQAECgUIBgAAAA==.Aloonarn:BAAANQAECgQIBAAAAA==.Alopix:BAAANQADCgYICgAAAA==.Alulla:BAAANQAECgQICAABNQAECgYIBQABAAAAAA==.Alunira:BAAANQAECgEIAQAAAA==.',
Am='Amberrfrost:BAAANQADCgUIBQAAAA==.Amize:BAAANQADCgYIBgAAAA==.',
An='Anabee:BAAANQADCggICAAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAAANQADCgYIBgAAAA==.Angrywar:BAAANQAECgEIAgAAAA==.Anharon:BAAANQADCgEIAQAAAA==.Ansatz:BAAANQADCgYICgAAAA==.',
Ap='Apokalypto:BAAANQADCgYIBwAAAA==.',
Ar='Arthannix:BAAANQADCgYIBwAAAA==.',
As='Astanis:BAAANQADCgYIBgAAAA==.Asteriia:BAAANQADCggIDwAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Av='Averettara:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Az='Azka:BAAANQAECgIIAgAAAA==.',
Ba='Babybilly:BAAANQADCggIEwAAAA==.Baelmon:BAAANQADCgQIBwAAAA==.Baludis:BAAANQADCgMIAwAAAA==.Bamff:BAAANQAECgEIAQAAAA==.Bast:BAAANQAECgYIBgAAAA==.',
Be='Benif:BAAANQAECgYICQAAAA==.Bertorod:BAAANQAECgIIAgAAAA==.',
Bi='Bigbitehotdo:BAAANQAECgUIBgAAAA==.Bighoney:BAAANQADCgQIBgAAAA==.Binkyfiasco:BAAANQADCggIDgAAAA==.Binny:BAAANQADCgQIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodstoned:BAAANQADCgQIBAAAAA==.Blueboy:BAAANQAECgEIAQAAAA==.',
Bo='Bonewrath:BAAANQABCgIIAgAAAA==.',
Br='Bridrystina:BAAANQADCgQIBAAAAA==.',
Bu='Burblbiblr:BAAANQADCgQIBAAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
Ca='Cambrier:BAAANQAECgQIBQAAAA==.Cameraop:BAAANQAECgQIBAAAAA==.Cardinal:BAAANQADCgQIBAAAAA==.Castbo:BAAANQADCgMIAwABNQAECgcIBwABAAAAAA==.',
Ce='Cellesstia:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Ch='Chatnoir:BAAANQADCggIEAAAAA==.Chestock:BAAANQADCgYIBgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Co='Colesiaw:BAAANQADCgQIBgAAAA==.',
Cr='Crnogorac:BAAANQADCgYIBgAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAECgYICAABAAAAAA==.',
Da='Dadstonks:BAAANQABCgQIBgAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dankbo:BAAANQAECgcIBwAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Despondent:BAAANQADCgEIAQAAAA==.Devildj:BAAANQADCgYIDQAAAA==.Dezadian:BAAANQADCgUICgAAAA==.',
Di='Dimitrios:BAAANQADCgYICwAAAA==.Dixxonciderr:BAAANQAECgcIDQAAAA==.',
Dm='Dmoe:BAAANQADCgUIBQAAAA==.',
Do='Doji:BAAANQADCgEIAQAAAA==.',
Du='Duplicate:BAAANQAECgYICgAAAA==.Dustdruid:BAAANQAECgYICwAAAA==.Dustmage:BAAANQADCggIEAAAAA==.',
Dw='Dwarr:BAAANQAECgIIAgAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBgAAAA==.',
Eg='Eggrolls:BAAANQAECgMIBAAAAA==.',
El='Ellcrys:BAAANQADCgcIDgAAAA==.Elletta:BAAANQADCgEIAQAAAA==.',
Eq='Eqo:BAAANQAECgUIBgAAAA==.',
Er='Erisian:BAAANQADCgQIBAAAAA==.Erkêios:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Es='Escherichia:BAAANQADCgIIAgAAAA==.Estheban:BAAANQAECgEIAQAAAA==.',
Fa='Face:BAAANQADCgQIBQAAAA==.Fairgrim:BAAANQADCgYICAAAAA==.Falin:BAAANQAECgQIBAAAAA==.Fanethben:BAAANQADCgIIAgAAAA==.Faqueueeight:BAAANQAECgUIBwAAAA==.Fatsloth:BAAANQADCgYICgAAAA==.Fatébringer:BAAANQADCgYIBgABNQADCgQIBAABAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Felcookies:BAAANQADCgYIDAAAAA==.',
Fi='Fimtastic:BAAANQADCgcIDQAAAA==.Finasy:BAAANQAECgEIAQAAAA==.Finnicka:BAAANQADCgYIDAAAAA==.Fistymisty:BAAANQAECgMIAwAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.',
Fr='Frostya:BAAANQADCgEIAQAAAA==.',
Ga='Galeriel:BAAANQAECgUIBQAAAA==.Garault:BAAANQADCgcIBwAAAA==.Gavered:BAAANQADCgIIAgAAAA==.',
Ge='Gekoni:BAAANQADCgYIBgAAAA==.Geotracker:BAAANQADCggIDgAAAA==.',
Go='Goolgame:BAAANQAECgUIBgAAAA==.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcIBwAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grirr:BAAANQAECgIIAwAAAA==.Gruldag:BAAANQAECgUICAAAAA==.Grullander:BAAANQAECgEIAQAAAA==.',
Gu='Guiguiie:BAAANQADCggIEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBAAAAA==.',
Ha='Halter:BAAANQADCgIIAgAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Hazzurd:BAAANQADCgcIDAAAAA==.',
He='Header:BAAANQAECgcICwAAAA==.Helane:BAAANQADCgUIBQAAAA==.Hermionee:BAAANQAECgEIAQAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAAANQAECgQIBAAAAA==.',
Ho='Holykoi:BAAANQAECgIIAgAAAA==.',
Hr='Hroarr:BAAANQADCgYIBgAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAAANQADCgUIBQAAAA==.Hélbrecht:BAAANQADCgYICAAAAA==.',
Ia='Iatros:BAAANQADCgIIAgAAAA==.',
In='Indravax:BAAANQADCgYIBgAAAA==.',
Iv='Ivantis:BAAANQADCgUIBwAAAA==.Ivie:BAAANQADCgIIAgAAAA==.',
Ja='Jaholypriest:BAAANQADCggICAAAAA==.Janjor:BAAANQAECgIIAgAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAAANQAECgQIBAAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQADCgYICwAAAA==.',
Jj='Jjdruid:BAAANQADCgUIBwAAAA==.',
Jo='Jollygreene:BAAANQADCgYICwAAAA==.',
Jp='Jpgigademon:BAAANQADCgIIAgAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Ka='Kalivan:BAAANQADCgYIBwAAAA==.Karametra:BAAANQADCgEIAQAAAA==.Kasmir:BAAANQAECgIIAgAAAA==.',
Ke='Kevv:BAAANQAECgQIBAAAAA==.',
Kh='Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgIIAgAAAA==.',
Ki='Killaarrow:BAAANQADCgcIDwAAAA==.',
Kl='Klay:BAAANQADCggICgAAAA==.',
Km='Kmarte:BAEANQAECgIIAgAAAA==.',
Kr='Kraggoryx:BAAANQAECgEIAQAAAA==.Kryesta:BAAANQAECgMIAwAAAA==.',
Kw='Kwarr:BAAANQAECgYICAAAAA==.',
La='Laganddecay:BAAANQABCgQICgAAAA==.Lalii:BAAANQADCgMIBAAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAECgYIBQABAAAAAA==.',
Le='Leasin:BAAANQAECgIIAgAAAA==.Lethendervis:BAAANQADCgEIAQAAAA==.',
Li='Liliauna:BAAANQAECgQIBQAAAA==.Lillynelazar:BAAANQADCggIEAABNQADCggIDgABAAAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgUIBgABAAAAAA==.Linithara:BAAANQAECgQIBgAAAA==.Littlehoosie:BAAANQAECgEIAQAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAEIAQABAAAAAA==.Loram:BAAANQADCgMIAwAAAA==.Lostgrip:BAAANQADCgYICAAAAA==.',
Lu='Lucthedk:BAAANQADCgUIBwAAAA==.Lunitari:BAAANQADCggICAAAAA==.Lunkbeck:BAAANQADCggIDQAAAA==.',
['Lø']='Lørd:BAAANQAECgQIBQAAAA==.',
Ma='Madik:BAAANQADCgEIAQAAAA==.Magicmegan:BAAANQADCgMIAwAAAA==.Malvean:BAAANQADCgUIBwAAAA==.Manasa:BAAANQADCgQIBgAAAA==.Marceline:BAAANQADCgcIDQAAAA==.Matresstains:BAAANQADCggIDQAAAA==.',
Mc='Mcdermott:BAAANQAECgIIAgAAAA==.',
Me='Melanius:BAAANQADCgcIDAAAAA==.Melranis:BAAANQADCgYICgAAAA==.',
Mi='Miluk:BAAANQADCgEIAQAAAA==.Misconduct:BAAANQADCggIDAAAAA==.',
Mo='Moomist:BAAANQADCgUICwAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Murdamoose:BAAANQADCgEIAQAAAA==.',
My='Mysteryx:BAAANQAECgEIAQAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.',
Ne='Nereza:BAAANQADCgYICwAAAA==.Nesquip:BAAANQADCgYIBgAAAA==.',
Ni='Nightforday:BAAANQAECgUICQAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noktas:BAAANQADCgYICwAAAA==.Nool:BAAANQADCgIIAwAAAA==.Norch:BAAANQADCggICAAAAA==.',
Ok='Oki:BAAANQADCgEIAQAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.',
Os='Oskaia:BAAANQAECgIIBAAAAA==.Osla:BAAANQADCgcIDQAAAA==.',
Pa='Paapineau:BAAANQADCggICAAAAA==.Packes:BAAANQAECgIIAgAAAA==.Pakkohruun:BAAANQAECgQIBQAAAA==.Pallywack:BAAANQADCgYICwAAAA==.Parthima:BAAANQAECgEIAQAAAA==.',
Ph='Phantomclone:BAAANQADCggIDgAAAA==.',
Pi='Piko:BAAANQADCggICAAAAA==.Piyo:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQAAAA==.Porkbuns:BAAANQADCggICAAAAA==.',
Pr='Precious:BAAANQADCgEIAgAAAA==.Priestymon:BAAANQADCgIIAgABNQAECgYICQABAAAAAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAAANQAECgQIBAABNQAECgYICAABAAAAAA==.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quaesitor:BAAANQADCgQIBwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAECgYICAABAAAAAA==.',
Ra='Raathya:BAAANQADCgQIBAAAAA==.Raeljin:BAAANQADCggIDgAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQADCgYICwAAAA==.Ratgamerlol:BAAANQAECgQIBAAAAA==.',
Re='Reckrunner:BAAANQADCgcICgAAAA==.Reneana:BAAANQADCgYICgAAAA==.',
Rh='Rhianonn:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.',
Ri='Richardluis:BAAANQADCgYIDAAAAA==.Rinehardtt:BAAANQAECgQIBAAAAA==.Rivër:BAAANQADCgQIBAAAAA==.',
Ro='Robbell:BAAANQAECgUIBQAAAA==.Rokyman:BAAANQADCgYIBgAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Rootsie:BAAANQADCgYIBgAAAA==.Roselynn:BAAANQAECgEIAQAAAA==.Rouby:BAAANQADCgYICwAAAA==.',
Ru='Ruerl:BAAANQAECgEIAQAAAA==.Runentug:BAAANQAECgYIBQAAAA==.Rustyspell:BAAANQADCgIIAgAAAA==.',
Sa='Saramon:BAAANQADCgcIGQAAAA==.Sassiberry:BAAANQADCgQIBQAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgEIAQAAAA==.Scrembiblion:BAAANQADCggIDwAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Sensjei:BAAANQADCgMIBAAAAA==.Separatist:BAAANQADCgMIAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shinyivie:BAAANQAECgQIBQAAAA==.Shãdøwzzxz:BAAANQADCgYIBwAAAA==.',
Sk='Skogr:BAAANQADCgIIAQAAAA==.Skädoosh:BAAANQADCgQIBAAAAA==.',
Sm='Smokeyhaze:BAAANQADCgMIAwAAAA==.Smokin:BAAANQADCgcIBwAAAA==.Smores:BAAANQADCgYIBgAAAA==.',
So='Solomonk:BAAANQADCgQIBAAAAA==.Solomus:BAAANQADCgYIBgAAAA==.Sonal:BAAANQADCgcIDQAAAA==.Soter:BAAANQADCgEIAQAAAA==.',
St='Stelltrain:BAAANQABCgIIAwAAAA==.Stormiee:BAAANQAECgIIAgABNQADCgIIAgABAAAAAA==.Stormroid:BAAANQADCgQIAgAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.',
Su='Sugarontop:BAAANQADCgIIAgAAAA==.Sunmx:BAAANQAECgQIBAAAAA==.',
Sw='Swurves:BAAANQADCgQIBQABNQADCggIDgABAAAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
Ta='Taedrum:BAAANQADCgYIBwAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Taloning:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Talonstryke:BAAANQAECgQIBQAAAA==.',
Te='Tenseiga:BAAANQADCgYIBgABNQAECgYIBgABAAAAAA==.',
Th='Theenforcer:BAAANQAECgYICQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Thetzin:BAAANQADCgUIBQAAAA==.Thickhobo:BAAANQADCgQIBAAAAA==.Thidwick:BAAANQADCggIDgAAAA==.Thingtwø:BAAANQADCggICAAAAA==.Thistle:BAAANQADCgYIBgAAAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titø:BAAANQADCgYIDQAAAA==.',
To='Tomorrow:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Totoo:BAAANQAECggIBQAAAA==.',
Tr='Tralis:BAEANQADCgYIBgAAAA==.Tranarra:BAAANQAECgEIAgAAAA==.Traylo:BAAANQADCggIDQAAAA==.',
Tv='Tvak:BAAANQADCgQIBgAAAA==.',
Tw='Twopump:BAAANQADCgcIDQAAAA==.',
Ul='Ulinova:BAAANQADCgUIBQAAAA==.',
Um='Umbryx:BAAANQADCgIIAgAAAA==.',
Un='Unholly:BAAANQADCgMIAwAAAA==.',
Ur='Uroro:BAAANQAECgYIBQAAAA==.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vainqueur:BAAANQADCggIDgAAAA==.Valienni:BAAANQADCgQICAAAAA==.Vandernum:BAAANQADCgUIBgAAAA==.Vandersius:BAAANQADCgUIBQAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Verymelon:BAAANQABCgIIAgABNQAECgQIBgABAAAAAA==.',
Vg='Vgx:BAAANQADCgUICQAAAA==.',
Vi='Viintage:BAAANQADCgYIBgAAAA==.Viridius:BAAANQADCgMIAwAAAA==.Vishouspayne:BAAANQADCgIIAQAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
['Vä']='Väelün:BAAANQADCgUICQABNQADCggIDgABAAAAAA==.',
Wa='Wachoosh:BAAANQADCgYIBgAAAA==.Waidmanns:BAAANQAECgQIBAAAAA==.',
Wh='Whatsaggro:BAAANQAECgIIAgAAAA==.Whatyamean:BAAANQAECgEIAQAAAA==.',
Wi='Wickedchick:BAAANQADCgMIBAAAAA==.Willowknight:BAAANQADCgYICgAAAA==.',
Wr='Wrongname:BAAANQADCggICgAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
['Xß']='Xß:BAAANQADCgEIAQAAAA==.',
Yo='Yogsothoth:BAEANQAECgQIBgAAAA==.',
Yu='Yulian:BAAANQADCgUIBQAAAA==.',
Za='Zaartyn:BAAANQAECgIIAgAAAA==.Zaater:BAAANQADCgIIAgAAAA==.',
Ze='Zeebeth:BAAANQAECgIIAgAAAA==.Zefi:BAAANQADCgYICQAAAA==.Zellek:BAAANQADCgYIBgAAAA==.',
Zy='Zyreth:BAAANQADCgUIBQAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQADCgQIBAABNQADCggIDAABAAAAAA==.',
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
