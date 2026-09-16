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

local lookup = {'Unknown-Unknown','Monk-Windwalker','Paladin-Protection','Warrior-Arms','Priest-Discipline','Priest-Holy','Evoker-Preservation','Evoker-Devastation','Druid-Balance','DemonHunter-Havoc','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAAANQAECgcIEgAAAA==.',
Ad='Adielia:BAAANQAECgMIAwAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgMIAwAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCgYICAAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQADCgUIBgABNQAECgIIAwABAAAAAA==.Airflash:BAABNQAECoEaAAICAAgJ7SGhBQAhAwACAAgJ7SGhBQAhAwAAAA==.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAAANQAECgUIBQABNQAECggIEQABAAAAAA==.',
Al='Alexious:BAABNQAECoEYAAIDAAgJ6yEiBAAVAwADAAgJ6yEiBAAVAwAAAA==.Aloonarn:BAAANQAECgQIBAAAAA==.Alopix:BAAANQAECgIIAgAAAA==.Alulla:BAAANQAFFAIIAgAAAA==.Alunira:BAAANQAECgYICgAAAA==.',
Am='Amberrfrost:BAAANQAECgIIAgAAAA==.Amize:BAAANQADCgYIBgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAAANQAECgIIAgAAAA==.Angrywar:BAAANQAECgEIAwAAAA==.Anharon:BAAANQADCgYIBwAAAA==.Ansatz:BAAANQAECgEIAQAAAA==.',
Ap='Apokalypto:BAAANQADCgYIBwAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Arthan:BAAANQADCggICAAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Astanis:BAAANQADCggIFgAAAA==.Asteriia:BAAANQAECgQIBAAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Av='Averettara:BAAANQADCggIEAABNQAECgUICgABAAAAAA==.',
Az='Azka:BAAANQAECgYICgAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAAANQAECgIIAwAAAA==.Baelmon:BAAANQADCgcICwAAAA==.Baludis:BAAANQADCgcICwAAAA==.Bamff:BAAANQAECgQIBgAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Bast:BAAANQAECggIEQAAAA==.Basthara:BAAANQADCggIEAABNQAECggIEQABAAAAAA==.',
Be='Benif:BAABNQAECoEYAAIEAAkJ6yPBEgAxAwAEAAkJ6yPBEgAxAwAAAA==.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAAANQAECgYIDQAAAA==.',
Bi='Bigbitehotdo:BAAANQAECgUIDwAAAA==.Bighoney:BAAANQADCgYIDAAAAA==.Binkyfiasco:BAAANQADCggIDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodstoned:BAAANQADCgQIBAAAAA==.Blueboy:BAAANQAECgUIBgAAAA==.',
Bo='Bonewand:BAAANQAECgEIAQAAAA==.Bonewrath:BAAANQABCgIIAgAAAA==.',
Br='Breadscrumb:BAAANQADCgUIBQAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.',
Bu='Burblbiblr:BAAANQADCgQIBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQADCgIIAgAAAA==.',
Ca='Cambrier:BAAANQAECgYIDwAAAA==.Cameraop:BAAANQAECgYIDgAAAA==.Cardinal:BAAANQADCgYICgAAAA==.Castbo:BAAANQAECgMIAwABNQAECgkJGgAFADYhAA==.',
Ce='Cellesstia:BAAANQADCgIIAgABNQADCgUICQABAAAAAA==.',
Ch='Chalada:BAAANQADCgEIAQABNQAECggICgABAAAAAA==.Chalastorm:BAAANQADCgYIBwABNQAECggICgABAAAAAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatnoir:BAAANQAECgQIBQAAAA==.Chestock:BAAANQADCgYIBgAAAA==.Chuggz:BAAANQAECgIIAgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Co='Codith:BAAANQADCgUIBQAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.',
Cr='Crnogorac:BAAANQAECggIAQAAAA==.',
Cu='Cuddlesworth:BAAANQAECgQIBAAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAIIAgABAAAAAA==.',
Da='Dadstonks:BAAANQABCgQIBgAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAAANQADCgYICAAAAA==.Dankbo:BAABNQAECoEaAAMFAAkJNiGEAQDhAgAFAAgJqx+EAQDhAgAGAAkJFxpBGQB7AgAAAA==.Darkivie:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCgQIBQAAAA==.Devildj:BAAANQAECgIIAgAAAA==.Dezadian:BAAANQADCgYIEAAAAA==.',
Dh='Dhampyra:BAAANQAECgUIBQAAAA==.',
Di='Dietmountdew:BAAANQADCgEIAQAAAA==.Dimitrios:BAAANQAECgEIAQAAAA==.Disolve:BAAANQAECggICQAAAA==.Dixxonciderr:BAABNQAECoEfAAMHAAkJARo1BwDdAgAHAAkJARo1BwDdAgAIAAIJdQoAJABhAAAAAA==.',
Dm='Dmoe:BAAANQADCggIEgAAAA==.',
Do='Doji:BAAANQADCgEIAQAAAA==.',
Dq='Dqe:BAAANQADCgYIBgAAAA==.',
Du='Duplicate:BAAANQAFFAEIAQAAAA==.Dustdruid:BAABNQAECoEUAAIJAAgJzBuhGwBoAgAJAAgJzBuhGwBoAgAAAA==.Dustlock:BAAANQAECgcIBwAAAA==.Dustmage:BAAANQADCggIEAAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
['Dó']='Dóru:BAAANQADCgYIBgAAAA==.',
Eg='Eggrolls:BAABNQAECoEXAAIEAAcJphJlVwDUAQAEAAcJphJlVwDUAQAAAA==.',
El='Ellcrys:BAAANQAECgYICwAAAA==.Elletta:BAAANQADCgEIAQAAAA==.',
Eq='Eqo:BAAANQAECgcIEgAAAA==.',
Er='Erisian:BAAANQADCgUIBwAAAA==.Erkêios:BAAANQADCggIDgABNQAECgcIEAABAAAAAA==.',
Es='Escherichia:BAAANQADCgYICAAAAA==.Estheban:BAAANQAECgQICAAAAA==.',
Fa='Face:BAAANQADCgQIBQAAAA==.Fairgrim:BAAANQADCggIEQAAAA==.Falin:BAAANQAECgYIEQAAAA==.Faqueuedark:BAAANQADCgYIBgABNQAECgkJHAAKALohAA==.Faqueueeight:BAABNQAECoEcAAIKAAkJuiH0AwB4AwAKAAkJuiH0AwB4AwAAAA==.Fatsloth:BAAANQAECgIIAgAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQADCgEIAQAAAA==.Felcookies:BAAANQAECgQIBAAAAA==.',
Fi='Fimtastic:BAAANQAECgQIBAAAAA==.Finasy:BAAANQAECgQIBgAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Fistymisty:BAAANQAECgYICQAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.',
Fr='Freezegarr:BAAANQADCgYIBwABNQAECgYICAABAAAAAA==.Frostya:BAAANQADCgEIAQAAAA==.',
Fu='Furearia:BAAANQABCgcICQAAAA==.',
Ga='Galeriel:BAABNQAECoEXAAIGAAkJbySvAgCIAwAGAAkJbySvAgCIAwAAAA==.Gallethline:BAAANQADCgYIBwAAAA==.Garault:BAAANQAECgIIAgAAAA==.Gavered:BAAANQADCgMIBAAAAA==.',
Ge='Gekoni:BAAANQADCgYIBgAAAA==.Geotracker:BAAANQAECgQIBgAAAA==.',
Go='Goolgame:BAABNQAECoEYAAMLAAgJzR90GQCpAgALAAcJ9B90GQCpAgAMAAMJzxpRcgDwAAAAAA==.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcICAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAAANQADCgUICQAAAA==.Gruldag:BAABNQAECoEbAAINAAkJxBTrPgCWAgANAAkJxBTrPgCWAgAAAA==.Grullander:BAAANQAECgQICAAAAA==.',
Gu='Guiguiie:BAAANQADCggIEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBAAAAA==.',
Ha='Hailey:BAEANQAECgYIBwABNQAFFAEIAgABAAAAAA==.Halter:BAAANQADCgMIAwAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Hazzurd:BAAANQAECgQIBAAAAA==.',
He='Header:BAABNQAECoEZAAMOAAkJuxYsEQBzAgAOAAkJuxYsEQBzAgAPAAUJ5wo2ewAtAQAAAA==.Heersbeest:BAAANQABCgIIAgAAAA==.Helane:BAAANQADCgUIBQAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAAANQAECgQICAAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAAANQAECgYIDQAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAECggICgABAAAAAA==.Holykoi:BAAANQAECgUICwAAAA==.',
Hr='Hroarr:BAAANQAECgYICAAAAA==.',
Hu='Humancarnage:BAAANQADCgIIAwAAAA==.Huuh:BAAANQADCgEIAQAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAAANQAECgMIBAAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgMIBAAAAA==.',
Ia='Iatros:BAAANQAECgEIAQAAAA==.',
Id='Idkno:BAAANQADCgQIBAAAAA==.',
In='Indravax:BAAANQADCgYIBgAAAA==.',
Iv='Ivantis:BAAANQADCgYIEgAAAA==.Ivie:BAAANQADCgUICQAAAA==.',
Ja='Jaholypriest:BAAANQAECgcICAAAAA==.Janjor:BAAANQAECgIIAgAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAAANQAECgcIEgAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQADCggIGwAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Jollygreene:BAAANQAECgEIAQAAAA==.Jonestu:BAAANQADCgIIAgAAAA==.',
Jp='Jpgigademon:BAAANQAECgEIAQAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Karametra:BAAANQADCgIIAgAAAA==.Karlldun:BAAANQADCggIDQAAAA==.Kasmir:BAAANQAECgYIDAAAAA==.',
Ke='Kevv:BAAANQAECgcIDAAAAA==.',
Kh='Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgIIAgAAAA==.',
Ki='Killaarrow:BAAANQAECgYIDAAAAA==.Kindleos:BAAANQADCgQIBAAAAA==.',
Kl='Klay:BAAANQAECgEIAgAAAA==.',
Km='Kmarte:BAEANQAECgQICQABNQAECgYIBgABAAAAAA==.Kmartt:BAEANQAECgYIBgAAAA==.',
Ko='Kosmicknight:BAAANQAECgMIAwAAAA==.',
Kr='Kraggers:BAAANQAECgQICAAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Kryesta:BAAANQAECgYIDgAAAA==.',
Kw='Kwarr:BAABNQAECoEYAAIQAAkJoRzGAwAMAwAQAAkJoRzGAwAMAwABNQAFFAIIAgABAAAAAA==.',
La='Laganddecay:BAAANQABCgcIDgAAAA==.Lalii:BAAANQADCgUICQAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAECgkJFQARAE8jAA==.',
Le='Leasin:BAAANQAECgQICgAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgEIAQAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAAANQAECgUIBwAAAA==.Lillynelazar:BAAANQAECgYICwABNQAECgMIAwABAAAAAA==.Lilsquirtboy:BAAANQADCgUIBQABNQAECgUIDwABAAAAAA==.Linithara:BAAANQAECgcIEwAAAA==.Littlehoosie:BAAANQAECggIAQAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAIIBQASAAYRAA==.Loram:BAAANQADCgQIBAAAAA==.Lostgrip:BAAANQAECgIIAgAAAA==.',
Lu='Lucthedk:BAAANQAECgMIBQAAAA==.Lukis:BAAANQADCgQIBAAAAA==.Lunitari:BAAANQADCggIDwAAAA==.Lunkbeck:BAAANQAECgEIAgAAAA==.',
['Lø']='Lørd:BAAANQAECgcIEQAAAA==.',
Ma='Madik:BAAANQADCgEIAQAAAA==.Magicmegan:BAAANQADCgMIAwAAAA==.Maladin:BAAANQAECgEIAQAAAA==.Malvean:BAAANQADCgUIBwAAAA==.Manasa:BAAANQAECgIIAgAAAA==.Marceline:BAAANQADCgcIDQAAAA==.Matresstains:BAAANQAECgUICAAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgQIBAAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAAANQADCgYICgAAAA==.Misconduct:BAAANQAECgIIAwAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQADCgYIEQAAAA==.Moonmx:BAAANQADCgEIAQAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAAANQAECgUICgAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Naniwa:BAAANQAECgMIAwAAAA==.Nazura:BAAANQADCgUICgAAAA==.',
Ne='Nereza:BAAANQADCgYIDAAAAA==.Nershog:BAAANQADCggICAAAAA==.Nesquip:BAAANQADCgYIBgAAAA==.',
Ni='Nightforday:BAABNQAECoEeAAITAAgJWyDMEADQAgATAAgJWyDMEADQAgAAAA==.Niko:BAAANQABCgUIBQAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noktas:BAAANQAECgEIAQAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIIAwAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgQIBAAAAA==.',
Op='Ophysia:BAAANQADCgYICAAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgUIBQAAAA==.',
Pa='Paapineau:BAAANQAECgEIAQAAAA==.Packes:BAAANQAECgYIDAAAAA==.Pakkohruun:BAAANQAECgcIEQAAAA==.Pallywack:BAAANQAECgQICQAAAA==.Parthima:BAAANQAECgQIBQAAAA==.',
Pe='Peppercat:BAAANQAECgEIAQAAAA==.Pettigrew:BAAANQADCgIIAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIAwAAAA==.Philomena:BAAANQADCgUICQAAAA==.',
Pi='Piggÿ:BAAANQAECgEIAQAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQAAAA==.Porkbuns:BAAANQAECgQICAAAAA==.',
Pr='Praedor:BAAANQADCgYIBgAAAA==.Precious:BAAANQADCgEIAgAAAA==.Priestymon:BAAANQADCgIIAgABNQAECgkJGAAEAOsjAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAAANQAFFAIIAgAAAA==.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIIAgAAAA==.Quaesitor:BAAANQADCgYIDwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAFFAIIAgABAAAAAA==.',
Ra='Raathya:BAAANQAECgIIAgAAAA==.Raeljin:BAAANQAECgQIBwAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQADCgYIDAAAAA==.Ratgamerlol:BAAANQAECgUIDwAAAA==.Rayennagrom:BAAANQADCggIEgAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAAANQADCgcIEAAAAA==.Redlocks:BAAANQADCgcIBwAAAA==.Reneana:BAAANQADCgYICgAAAA==.Restbo:BAAANQAECgIIAgABNQAECgkJGgAFADYhAA==.',
Rh='Rhianonn:BAAANQADCgIIAgABNQADCgUICQABAAAAAA==.',
Ri='Richardluis:BAAANQADCggIEAAAAA==.Rinehardtt:BAAANQAECggIDwAAAA==.Riverstyxx:BAAANQADCgIIAgAAAA==.Rivër:BAAANQADCgQIBAAAAA==.',
Ro='Robbell:BAAANQAECgYIEQAAAA==.Rokyman:BAAANQAECgQIBQAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Rootsie:BAAANQADCgYIEgAAAA==.Roselynn:BAAANQAECgUICgAAAA==.Rouby:BAAANQAECgEIAQAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAAANQAECgUICgAAAA==.Runentug:BAABNQAECoEVAAIRAAkJTyP4BAB0AwARAAkJTyP4BAB0AwAAAA==.Rustyspell:BAAANQADCgIIAgAAAA==.',
Sa='Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sassiberry:BAAANQADCgYIEAAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAAANQAECgUIBQAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Sensjei:BAAANQADCgUICAAAAA==.Separatist:BAAANQADCgMIAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgMIAwAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAAANQAECgQICQAAAA==.Shroomjuice:BAAANQADCgQIBAAAAA==.Shãdøwzzxz:BAAANQAECgEIAQAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQABAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sm='Smokeyhaze:BAAANQAECgQIBAAAAA==.Smokin:BAAANQAECgEIAQAAAA==.Smolther:BAAANQADCgYIBgAAAA==.Smores:BAAANQADCgYIBgAAAA==.',
So='Solomonk:BAAANQAECgIIAgAAAA==.Solomus:BAAANQAECgEIAQAAAA==.Sonal:BAAANQAECgQIBwAAAA==.Soter:BAAANQADCgIIAgAAAA==.',
St='Stelltrain:BAAANQABCgIIAwAAAA==.Stormiee:BAAANQAECgYIDAABNQADCgUICQABAAAAAA==.Stormroid:BAAANQAECgEIAQAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.',
Su='Sugarontop:BAAANQADCgQIBAAAAA==.Sunmx:BAAANQAECgUIDQAAAA==.',
Sw='Swurves:BAAANQAECgIIAwAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
Ta='Taedrum:BAAANQAECgEIAQAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQADCgEIAQAAAA==.Talonfel:BAAANQADCgQIBAABNQAECgYIEAABAAAAAA==.Taloning:BAAANQADCgYIBgABNQAECgYIEAABAAAAAA==.Talonstryke:BAAANQAECgYIEAAAAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Tenseiga:BAAANQADCggIDgABNQAECggIEQABAAAAAA==.Tevers:BAAANQADCgEIAQAAAA==.',
Th='Thaalion:BAAANQADCggICAAAAA==.Thardal:BAAANQAECgEIAgAAAA==.Thebigshot:BAAANQADCggICQAAAA==.Theenforcer:BAABNQAECoEZAAIUAAgJAQu0UwCpAQAUAAgJAQu0UwCpAQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Thetzin:BAAANQAECgEIAQAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAAANQAECgQIBgAAAA==.Thingtwø:BAAANQAECgEIAQAAAA==.Thistle:BAAANQADCgYIBgAAAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titø:BAAANQADCgYIDQABNQADCgcIBwABAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICAAAAA==.',
To='Tokadin:BAAANQABCgQIBAAAAA==.Tomorrow:BAAANQADCgcIDQABNQAECgEIAQABAAAAAA==.Totoo:BAAANQAECggICgAAAA==.',
Tr='Tralis:BAEANQADCggIDgAAAA==.Tranarra:BAAANQAECgMICQAAAA==.Traylo:BAAANQAECgEIAQAAAA==.',
Tv='Tvak:BAAANQAECgUICwAAAA==.',
Tw='Twopump:BAAANQAECgQIBwAAAA==.',
['Tó']='Tónka:BAAANQADCgcIBwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgEIAgAAAA==.',
Um='Umbryx:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Un='Unholly:BAAANQAECgIIAwAAAA==.',
Ur='Uroro:BAAANQAECggIEwABNQAFFAIIAgABAAAAAA==.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vainqueur:BAAANQAECgIIAwAAAA==.Valienni:BAAANQADCgYIDgAAAA==.Vanderius:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgQIBAAAAA==.Vandernum:BAAANQAECgIIAgAAAA==.Vandersius:BAAANQADCggICwAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQABCgUIBgABNQAECggIGQALAFMaAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAAANQAECgQIBgAAAA==.',
Vi='Vielitre:BAAANQADCgIIAgAAAA==.Viintage:BAAANQAECgQIBQAAAA==.Viridius:BAAANQADCgMIAwAAAA==.Vishouspayne:BAAANQADCgQIBQAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
['Vä']='Väelün:BAAANQAECgQICAAAAA==.',
Wa='Wachoosh:BAAANQADCgYIDwAAAA==.Waidmanns:BAAANQAECgcIDAAAAA==.',
Wh='Wham:BAAANQADCgUIBwAAAA==.Whatsaggro:BAAANQAECgUICgAAAA==.Whatyamean:BAAANQAECgIIAgAAAA==.Whoami:BAAANQADCggICAAAAA==.Whoangry:BAAANQADCgUIBQAAAA==.Whomonk:BAAANQADCgcIDAAAAA==.',
Wi='Wickedchick:BAAANQADCgUICQAAAA==.Willowknight:BAAANQADCgYICgAAAA==.',
Wr='Wrongname:BAAANQAECgIIAwAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
['Xß']='Xß:BAAANQADCgIIBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIBwAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEANQAECgQIDAAAAA==.',
Yu='Yulian:BAAANQADCgcIDgAAAA==.',
Za='Zaartyn:BAAANQAECgcIDQAAAA==.Zaater:BAAANQAECgEIAQAAAA==.Zalin:BAAANQADCggICAAAAA==.',
Ze='Zeebeth:BAAANQAECgYIDQAAAA==.Zefi:BAAANQADCgYICQAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Zerokai:BAAANQADCgYIBgAAAA==.',
Zo='Zorosenpai:BAAANQADCgIIAgABNQAECgYIDwABAAAAAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Âr']='Ârtemis:BAAANQADCggICAABNQAECggIEQABAAAAAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQADCgYICgABNQAECgIIAwABAAAAAA==.',
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
