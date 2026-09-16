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

local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Warrior-Arms','Mage-Frost','Mage-Arcane','Evoker-Devastation','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Shadow','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abdess:BAAANQADCggIDgAAAA==.',
Ad='Adaila:BAAANQAECgYIDgAAAA==.',
Ai='Aiir:BAAANQADCgcIEgAAAA==.',
Aj='Ajaki:BAAANQADCgMIAwAAAA==.Ajaxstar:BAAANQABCgYICwAAAA==.',
Al='Alethe:BAAANQAECgIIAgAAAA==.Alfivin:BAAANQADCgUIDgAAAA==.All:BAAANQAECgUIBgAAAA==.Almondor:BAAANQADCgYIBgAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgAAAA==.Ambridgerose:BAAANQADCggIDwAAAA==.Ammariel:BAAANQADCggICAAAAA==.',
Ap='Apocalypsus:BAAANQADCgYIDAAAAA==.Appolyin:BAAANQAECgIIAwAAAA==.',
Ar='Arlan:BAAANQADCgIIAgAAAA==.',
At='Athenâ:BAAANQAECgQIBgAAAA==.',
Au='Audrac:BAAANQADCgEIAQAAAA==.',
Av='Availis:BAAANQADCggIDgAAAA==.Avari:BAAANQADCgMIAwABNQADCggIEQABAAAAAA==.',
Aw='Awawa:BAAANQADCgQIBAAAAA==.',
Az='Azariel:BAAANQAECgYICwAAAA==.Azorahai:BAAANQADCggICwAAAA==.Azshalia:BAAANQADCgUIDgAAAA==.',
Ba='Bacardiand:BAAANQAECgYIEAAAAA==.Baishu:BAAANQAECgYIDQAAAA==.Banilibug:BAAANQADCgcIDAAAAA==.Baraddur:BAAANQADCgQIBgAAAA==.Baradun:BAAANQABCgYICQAAAA==.Barrymanalow:BAAANQAECgMIAwAAAA==.',
Be='Bearclaw:BAAANQADCgUIBQAAAA==.',
Bl='Blackout:BAAANQAECgEIAgABNQAECgcIDwACACIYAA==.Bluerabbit:BAAANQADCgYICwABNQAECgYIDwABAAAAAA==.',
Bo='Bobbybrady:BAAANQADCgUICgAAAA==.Bokni:BAAANQADCgYIBgAAAA==.',
Br='Brayk:BAAANQADCgIIAgAAAA==.',
Bu='Bufforc:BAAANQADCgYIBgAAAA==.Buildie:BAAANQADCgcIBwAAAA==.Bushwhacker:BAAANQADCgUIBQAAAA==.Butterbean:BAAANQAECgQIBQAAAA==.',
Ca='Capziesh:BAAANQADCgUIBgAAAA==.Carch:BAEANQADCgUIBQAAAA==.Catameringue:BAAANQAECgYICwAAAA==.',
Ch='Chicxulub:BAAANQADCgYIDAAAAA==.Chonkyninja:BAAANQAECgQIBAAAAA==.Choroksaek:BAAANQADCgYIBgAAAA==.',
Cl='Classfantasy:BAAANQAECgYICwAAAA==.',
Co='Cool:BAAANQADCgcIBwAAAA==.',
Ct='Cthruthyveil:BAAANQADCgUIEAABNQADCgcIBwABAAAAAA==.',
Cy='Cythrandir:BAAANQADCgIIAgABNQAECgYIDAABAAAAAA==.',
Da='Dany:BAAANQADCgYICwAAAA==.Darkriff:BAAANQABCgMIAwAAAA==.Daruta:BAAANQADCgQIBgAAAA==.Daytona:BAAANQADCggIEwAAAA==.',
Dd='Ddccssff:BAAANQADCgYIDQAAAA==.',
De='Deathcoiled:BAAANQADCggIEAAAAA==.Demonx:BAAANQAECgMIBgAAAA==.Dethrahzen:BAAANQADCggIFwAAAA==.',
Di='Disektor:BAAANQAECgQIBAAAAA==.',
Dk='Dkray:BAAANQADCgYICgABNQADCgcICwABAAAAAA==.',
Do='Dotsfordayz:BAAANQADCgcICwABNQAECgIIBAABAAAAAA==.',
Dr='Dronesworn:BAAANQADCgUICgAAAA==.Drstránge:BAAANQAECgIIAgAAAA==.',
Du='Dugatotems:BAAANQAECgYIDQAAAA==.Dunkle:BAABNQAECoEQAAIDAAcJxRJyVgDYAQADAAcJxRJyVgDYAQAAAA==.Duskhawk:BAAANQADCggIGgAAAA==.',
Dy='Dynxy:BAAANQADCgYIBgAAAA==.',
Eb='Ebonise:BAAANQADCgcIBwAAAA==.',
El='Elivien:BAAANQADCgIIAgABNQADCggIEQABAAAAAA==.Ellechero:BAAANQADCgYIFAAAAA==.',
Er='Eredin:BAAANQADCgMIAwAAAA==.Erommêl:BAAANQADCgUICgAAAA==.',
Fa='Farsha:BAAANQADCgYIBgABNQADCggIEQABAAAAAA==.',
Fe='Fextrius:BAAANQADCggIFQAAAA==.',
Fr='Frthckr:BAAANQADCgIIAgAAAA==.',
Ga='Gazebo:BAAANQADCgIIAgAAAA==.',
Ge='Genghis:BAAANQAECggIAQAAAA==.',
Gh='Ghast:BAAANQAECgUICAAAAA==.',
Gi='Giddley:BAAANQABCgMIAwAAAA==.Gigaflare:BAABNQAECoERAAMEAAcJygafDwDtAAAFAAcJXANQuwBAAQAEAAUJhgifDwDtAAAAAA==.',
Gl='Gladîator:BAAANQADCgEIAQAAAA==.Glahmgold:BAAANQADCggIDAAAAA==.',
Go='Goatale:BAAANQAECgUICgAAAA==.Goatseer:BAAANQAECgYICwAAAA==.Goatwizard:BAAANQAECgMIBAAAAA==.Gobblynn:BAAANQADCggIFgAAAA==.Goldvalkyrie:BAAANQADCgUIBQAAAA==.Golokan:BAAANQADCggIEQAAAA==.',
Gr='Grandpawolf:BAAANQADCggIFwAAAA==.Graymoon:BAAANQADCgQICAAAAA==.Greywings:BAAANQADCgIIAgAAAA==.Grimroxs:BAAANQADCggIFwAAAA==.Griptape:BAAANQAECgIIBAAAAA==.',
['Gå']='Gålahad:BAAANQADCgcIBwAAAA==.',
Ha='Handerbug:BAAANQAECgYIDwAAAA==.Handiebug:BAAANQADCgYIBgABNQAECgYIDwABAAAAAA==.',
He='Heiler:BAAANQAECgMIBgAAAA==.',
Hi='Hi:BAAANQADCgcIBwAAAA==.',
Ho='Hogglethorp:BAAANQAECgIIAgAAAA==.Hokis:BAAANQADCgcIBwAAAA==.Holyhooters:BAAANQADCgUICgAAAA==.Horns:BAAANQADCgUIDgAAAA==.',
Hr='Hruroth:BAAANQADCgMIBAAAAA==.',
Id='Idontrez:BAAANQAECgEIAQAAAA==.',
Il='Illadron:BAAANQADCgYIBgAAAA==.',
In='Inala:BAAANQADCgQIBAAAAA==.Infuzed:BAABNQAECoEPAAICAAcJIhguGAAaAgACAAcJIhguGAAaAgAAAA==.',
Io='Iove:BAAANQAECgUICAAAAA==.',
It='Itsmykitty:BAAANQABCgIIAgABNQADCggIBgABAAAAAA==.',
Ja='Jacksus:BAAANQAECgQIBgAAAA==.',
Jd='Jdbud:BAAANQADCgUICgAAAA==.Jdpot:BAAANQADCgcIDgAAAA==.',
Je='Jenaaidy:BAAANQADCgYIEAAAAA==.Jesko:BAAANQADCgUICAAAAA==.',
Jo='Joedavola:BAAANQADCgUICAAAAA==.Jooshie:BAAANQAECgIIAwABNQAECgYIDwABAAAAAA==.Jooshy:BAAANQAECgYIDwAAAA==.Josher:BAAANQADCgEIAQABNQAECgYIDwABAAAAAA==.Joshieboba:BAAANQADCgMIAwABNQAECgYIDwABAAAAAA==.Joyzee:BAAANQADCgcIEQAAAA==.',
Ju='Judge:BAAANQADCggIAwAAAA==.',
Jy='Jynrokka:BAAANQADCggIHAAAAA==.',
Ka='Kanati:BAAANQADCgUIBQAAAA==.Katasaria:BAABNQAECoEZAAIDAAgJ7iFqGgD5AgADAAgJ7iFqGgD5AgAAAA==.Katiebug:BAAANQADCggIBwAAAA==.Katiekat:BAAANQADCgQIBgAAAA==.Kaycee:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Kayceedilla:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Kaycer:BAAANQAECgEIAQAAAA==.',
Ke='Keeps:BAAANQADCgEIAQAAAA==.Kestrell:BAAANQAECgIIAgAAAA==.',
Kh='Khorlock:BAAANQAECgQICwAAAA==.Khorus:BAAANQAECgUICgAAAA==.',
Ki='Kirana:BAAANQADCgcIFAAAAA==.',
Ko='Koalateectrl:BAAANQADCgUIBQAAAA==.',
Kr='Kravin:BAAANQADCggIFQAAAA==.',
Ku='Kudrani:BAAANQADCgQIBwABNQADCggIEQABAAAAAA==.',
Ky='Kynnas:BAAANQAECgcIEQAAAA==.',
La='Laneywine:BAAANQABCgEIAQAAAA==.Larlifax:BAAANQADCgcIBwAAAA==.Lauxy:BAAANQAECgYICAAAAA==.',
Le='Leonuss:BAABNQAECoEWAAIDAAgJAyNeEwAsAwADAAgJAyNeEwAsAwAAAA==.Levìstus:BAAANQADCggIHAAAAA==.Leylaní:BAAANQAECgMIBgAAAA==.',
Li='Lillinth:BAAANQAECgQIBAAAAA==.Lilmagedude:BAAANQAECgEIAgAAAA==.Lilmissblue:BAAANQADCgcIBwAAAA==.Linoir:BAAANQAECgYIDwAAAA==.',
Lo='Loroessan:BAAANQADCgIIAgAAAA==.',
Lu='Lucylawladin:BAAANQADCgQIBAAAAA==.',
Ly='Lykios:BAAANQADCgYIBgAAAA==.Lythea:BAAANQADCgMIAwABNQAECgcIEQAGAHgZAA==.Lytheum:BAABNQAECoERAAIGAAcJeBl/DAAfAgAGAAcJeBl/DAAfAgAAAA==.',
Ma='Magikon:BAAANQADCgEIAQAAAA==.Magista:BAAANQADCgEIAQAAAA==.Malachar:BAAANQADCggIHAAAAA==.Malboro:BAAANQADCggIDwAAAA==.Maled:BAAANQADCgYIEAAAAA==.',
Me='Meldin:BAAANQAECgMIAwAAAA==.Method:BAAANQAECgYIDwAAAA==.',
Mi='Miannya:BAAANQAECgYIDwAAAA==.Mignons:BAAANQADCggIFwAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mineos:BAAANQAECgEIAQAAAA==.Minipedro:BAAANQADCggIDwABNQAECggIGAACAGsdAA==.Mirmidon:BAAANQABCgUICgAAAA==.Missingparts:BAAANQAECgEIAQAAAA==.Mistamiso:BAAANQADCgIIAgABNQAECgcIDwACACIYAA==.Mistrmiso:BAAANQADCgEIAQABNQAECgcIDwACACIYAA==.',
Mo='Moahuntress:BAAANQADCgUICQAAAA==.Moonlyt:BAAANQADCggIFQAAAA==.Morgaine:BAAANQADCgYICQABNQADCgcIBwABAAAAAA==.Morn:BAAANQAECgYICwAAAA==.',
My='Myra:BAAANQADCgMIAwAAAA==.Mystu:BAAANQADCgYIBgAAAA==.',
Na='Nadià:BAAANQADCgUIDAAAAA==.',
Ne='Needagrip:BAAANQAECgMIBgAAAA==.Netherid:BAAANQABCgQIBAAAAA==.',
Ny='Nystannia:BAAANQADCgEIAQABNQADCggIEQABAAAAAA==.',
Oo='Oor:BAAANQAECgMIAwABNQAECgYIBwABAAAAAA==.',
Or='Orlandbro:BAAANQAECgYIDwAAAA==.',
Os='Oshiokiyo:BAAANQADCggIEwAAAA==.',
Pa='Patchs:BAAANQADCgYICwAAAA==.Pawradox:BAAANQAECgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgYICwAAAA==.',
Pl='Plina:BAAANQAECgMIBgAAAA==.',
Po='Poshiesty:BAAANQADCgYIBgAAAA==.Potatolor:BAAANQAECgEIAQAAAA==.',
Pu='Pulli:BAAANQADCgQIBAAAAA==.Pusinmyboot:BAAANQADCgEIAQAAAA==.',
Pv='Pve:BAAANQAECgUIEQAAAA==.',
Ra='Raehanji:BAAANQADCgQIBAAAAA==.Raiina:BAAANQAECgUICgAAAA==.Rains:BAAANQADCgUIDAAAAA==.Rathane:BAABNQAECoEaAAIHAAgJXBgJKQBbAgAHAAgJXBgJKQBbAgAAAA==.Razhj:BAAANQADCgIIAgAAAA==.',
Re='Reapr:BAAANQAECgMIBgAAAA==.Redrabbit:BAAANQADCgYIDAAAAA==.Rexx:BAAANQADCgYICgAAAA==.',
Rh='Rhapsody:BAAANQADCggIHAAAAA==.',
Ri='Rizzwan:BAAANQADCgUICgAAAA==.',
Ru='Runecleaver:BAAANQAECgUICgABNQAECgYIBwABAAAAAA==.Ruw:BAAANQADCggIGwAAAA==.',
Sa='Sardroth:BAABNQAECoERAAIIAAcJvhpuIwAeAgAIAAcJvhpuIwAeAgAAAA==.Satavara:BAAANQADCggIHAAAAA==.',
Sh='Shapòópy:BAAANQADCgcIFgAAAA==.Sharius:BAAANQADCggIBgAAAA==.Shavv:BAAANQADCgQIBgAAAA==.Shiera:BAAANQAECgUICQAAAA==.',
Si='Sightlightx:BAAANQADCggIFwAAAA==.Sigs:BAAANQADCgYIBgAAAA==.Silvershine:BAAANQADCggICwAAAA==.Siryn:BAAANQADCgYIEAAAAA==.',
Sl='Slaphaschel:BAAANQADCgMIAwAAAA==.',
Sm='Smallest:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Sp='Sparkelynn:BAAANQADCgQIBgAAAA==.Spinlock:BAAANQADCgQIBAAAAA==.Spitfyre:BAAANQADCggICgAAAA==.',
St='Stonehammer:BAAANQADCgUIBQAAAA==.',
Su='Susa:BAAANQADCgMIBAAAAA==.',
Sy='Sylesta:BAAANQAECgYIDgAAAA==.Syrden:BAAANQADCggIDAABNQAECgYIDwABAAAAAA==.',
Ta='Talís:BAAANQADCgYICQAAAA==.',
Te='Teremen:BAAANQADCgUICQABNQAFFAUICAAJAO8YAA==.',
Th='Thandas:BAAANQADCgUIBwAAAA==.Thniper:BAAANQAECgQICgAAAA==.',
Ti='Tiamaria:BAAANQAECgYIDwAAAA==.',
Tr='Trilbey:BAAANQADCgYICwAAAA==.',
Tw='Twittch:BAAANQABCgEIAQAAAA==.',
Ty='Tyinviril:BAACNQAFFIEIAAIJAAUJ7xgyAQDWAQAJAAUJ7xgyAQDWAQA1AAQKgSIAAgkACQkzJq0AANwDAAkACQkzJq0AANwDAAAA.Tyvireth:BAAANQADCggIDgABNQAFFAUICAAJAO8YAA==.',
Ve='Veraz:BAAANQAECgcIEQAAAA==.',
Vo='Vonawesome:BAAANQADCgYIDQAAAA==.Vorpalblade:BAAANQAECgYIDwAAAA==.',
Vy='Vyraal:BAAANQADCgUICQAAAA==.',
Wa='Warloque:BAAANQADCgUIBgAAAA==.Warpsmithoor:BAAANQAECgYIBwAAAA==.',
We='Wend:BAABNQAECoESAAIKAAcJABzaAABmAgAKAAcJABzaAABmAgAAAA==.Weywey:BAAANQADCggIEAAAAA==.',
Wo='Wobblerslock:BAAANQADCgQICAABNQADCgcICQABAAAAAA==.',
Wr='Wram:BAAANQADCgcIBwAAAA==.Wreckturd:BAAANQADCggIEgABNQAECgUICgABAAAAAA==.',
Wy='Wychlord:BAAANQAECgEIAQAAAA==.',
Xe='Xenophilious:BAAANQADCgYICgAAAA==.',
Xi='Xiomara:BAAANQADCgQIBgAAAA==.Xiøn:BAAANQAECgIIAgAAAA==.',
Yn='Yn:BAAANQADCgIIAgAAAA==.',
Ze='Zelios:BAAANQADCgYIBgAAAA==.',
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
