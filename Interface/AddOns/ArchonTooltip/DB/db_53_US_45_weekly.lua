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

local lookup = {'Priest-Shadow','Shaman-Restoration','Unknown-Unknown','Priest-Holy','Priest-Discipline','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Hunter-BeastMastery','Druid-Restoration','Shaman-Elemental','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Warlock-Destruction','Mage-Frost','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Unholy','Druid-Guardian','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Paladin-Protection','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Frost','Paladin-Holy','Warrior-Protection','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adaila:BAABNQAECoEaAAIBAAgKKAiPNABXAQABAAgKKAiPNABXAQAAAA==.',
Ai='Aiir:BAAANQAECgMIBQAAAA==.',
Aj='Ajaki:BAAANQADCgMIAwAAAA==.Ajaxstar:BAAANQAECgEJAQAAAA==.',
Al='Alethe:BAAANQAECgcIEwAAAA==.Alfivin:BAAANQAECgEJAQAAAA==.All:BAAANQAECgYIEgAAAA==.Almondor:BAAANQADCgYIBgAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgAAAA==.Ambridgerose:BAAANQADCggIDwAAAA==.Ammariel:BAAANQAECgQIBQAAAA==.',
An='Antiwend:BAAANQAECgMIAwAAAA==.',
Ap='Apocalypsus:BAAANQADCgcIDgAAAA==.Appolyin:BAAANQAECgQJBgAAAA==.',
Ar='Arlan:BAAANQADCgIIAgAAAA==.',
As='Ashtomb:BAAANQADCgYIBgABNQAECggIHAACAHweAA==.',
At='Athenâ:BAAANQAECgQJCgAAAA==.',
Au='Audarah:BAAANQADCggIFAAAAA==.Audrac:BAAANQADCgEIAQAAAA==.',
Av='Availis:BAAANQADCggIDgAAAA==.Avari:BAAANQADCgMIAwABNQADCggIEQADAAAAAA==.',
Aw='Awawa:BAAANQADCgQIBAAAAA==.',
Az='Azariel:BAABNQAECoEgAAQEAAkKEAc3cQCRAQAEAAgK6Ac3cQCRAQAFAAEKSAFhLQAdAAABAAEKzgDshAAQAAAAAA==.Azorahai:BAAANQAECgUICQAAAA==.Azshalia:BAAANQAECgMIBgAAAA==.',
Ba='Bacardiand:BAABNQAECoEdAAIGAAkKDxbKDACIAgAGAAkKDxbKDACIAgAAAA==.Baishu:BAABNQAECoEfAAMHAAkKoxn1FgDEAgAHAAgKnxz1FgDEAgAIAAEKwwEeaAAhAAAAAA==.Balfazar:BAAANQAECgQIBgAAAA==.Banilibug:BAAANQADCgcIDAAAAA==.Baraddur:BAAANQADCgQIBgAAAA==.Baradun:BAAANQABCgYJCQAAAA==.Barrymanalow:BAAANQAECgYIEwAAAA==.',
Be='Bearclaw:BAAANQADCgUIBQAAAA==.Beorngoat:BAAANQAECgUIBQAAAA==.',
Bl='Blackout:BAAANQAECgMIBgABNQAECggIIAAHAHoZAA==.Bluerabbit:BAAANQAECgEIAgABNQAECgkJJgAJAEMkAA==.',
Bo='Bobbybrady:BAAANQADCgUICgAAAA==.Bokni:BAAANQADCgYIBgAAAA==.',
Br='Brayk:BAAANQADCgIIAgAAAA==.',
Bu='Bufforc:BAAANQADCgYIBgAAAA==.Buildie:BAAANQADCgcIBwAAAA==.Bushwhacker:BAAANQAECgEIAQAAAA==.Butterbean:BAABNQAECoEaAAIKAAkKXhn+MgCwAgAKAAkKXhn+MgCwAgAAAA==.',
Ca='Calice:BAAANQADCgMIAwAAAA==.Capziesh:BAAANQADCgUIBgAAAA==.Carch:BAEANQADCgUIBQAAAA==.Catameringue:BAABNQAECoEkAAMLAAgKTCPPCAAfAwALAAgKTCPPCAAfAwAJAAEK2wVhsAAfAAAAAA==.',
Ch='Chicxulub:BAAANQADCgYIDAAAAA==.Chonkyninja:BAAANQAECgQJBAAAAA==.Choroksaek:BAAANQADCgYIEgAAAA==.',
Cl='Classfantasy:BAABNQAECoEhAAMMAAkKQhQrQgBBAgAMAAkKQhQrQgBBAgACAAUKVwbqugDJAAAAAA==.',
Co='Cool:BAAANQADCgcIBwABNQAECgUIAwADAAAAAA==.',
Ct='Cthruthyveil:BAAANQAECgQIBgAAAA==.',
Cu='Cursè:BAAANQABCgIIAgABNQADCggIBgADAAAAAA==.',
Cy='Cythrandir:BAAANQADCgQICAABNQAECgkJHwANAF8aAA==.',
Da='Dany:BAAANQADCgYICwAAAA==.Darkriff:BAAANQABCggICwAAAA==.Daruta:BAAANQADCgQIBgAAAA==.Daytona:BAAANQAECgQICQAAAA==.',
Dd='Ddccssff:BAAANQAECgMIBgAAAA==.',
De='Deathcoiled:BAAANQAECgIIAgAAAA==.Demonx:BAABNQAECoEbAAIOAAcKYx17RgBhAgAOAAcKYx17RgBhAgAAAA==.Dethrahzen:BAAANQAECgEIAgAAAA==.',
Di='Dindunuthin:BAAANQADCgMIAwAAAA==.Dipika:BAAANQAECgQIBAAAAA==.Disektor:BAAANQAECgYIEAAAAA==.',
Dk='Dkray:BAAANQAECgUIDAAAAA==.',
Do='Donorli:BAAANQADCgYIBgAAAA==.Dotsfordayz:BAAANQAECgEIAwABNQAECgEIAQADAAAAAA==.',
Dr='Dronesworn:BAAANQADCgUICgAAAA==.Drstránge:BAAANQAECgQIBgAAAA==.',
Du='Dugatotems:BAABNQAECoEhAAMCAAgKjha4WwDOAQACAAgKjha4WwDOAQAMAAgKtwp6agCwAQAAAA==.Dunkle:BAABNQAECoEkAAIPAAkKjBgiUgB4AgAPAAkKjBgiUgB4AgAAAA==.Duskhawk:BAAANQAECgQICQAAAA==.',
Dy='Dynxy:BAAANQADCgYIBgAAAA==.',
Eb='Ebonise:BAAANQADCgcIBwABNQAECgQIBgADAAAAAA==.',
El='Elivien:BAAANQADCgIIAgABNQADCggIEQADAAAAAA==.Ellechero:BAAANQADCggIKwAAAA==.',
Eo='Eogimboonn:BAAANQADCgYIBgAAAA==.',
Er='Eredin:BAAANQADCgMIAwAAAA==.Erinna:BAAANQAECgIIAgAAAA==.Erommêl:BAAANQAECgMIAwAAAA==.',
Fa='Farsha:BAAANQADCgYIBgABNQADCggIEQADAAAAAA==.',
Fe='Fextrius:BAAANQAECgQICQAAAA==.',
Fr='Frthckr:BAAANQADCgIIAgAAAA==.',
Ga='Gazebo:BAAANQADCgIJAgAAAA==.',
Ge='Genghis:BAAANQAECggIAQAAAA==.',
Gh='Ghast:BAABNQAECoEwAAMOAAgK2A01dwDSAQAOAAgKYQ01dwDSAQAQAAIK6AqMXABjAAAAAA==.',
Gi='Giddley:BAAANQABCgMIAwAAAA==.Gigaflare:BAABNQAECoElAAMRAAkKbwhtFwAaAQANAAgKswRC8QCCAQARAAYKKQptFwAaAQAAAA==.',
Gl='Gladîator:BAAANQADCgEJAQAAAA==.Glahmgold:BAAANQAECgQIBAAAAA==.',
Go='Goatale:BAABNQAECoEhAAISAAgKlh7XEgCjAgASAAgKlh7XEgCjAgAAAA==.Goatseer:BAABNQAECoEZAAIGAAgK2BgRDgBxAgAGAAgK2BgRDgBxAgAAAA==.Goatwizard:BAAANQAECgMIBAAAAA==.Gobblynn:BAAANQADCggIFgAAAA==.Goldvalkyrie:BAAANQADCgUIBQAAAA==.Golokan:BAAANQADCggIEQAAAA==.',
Gr='Grandpawolf:BAAANQAECgUIBgAAAA==.Graymoon:BAAANQADCgQICAAAAA==.Greywings:BAAANQAECgIIAwAAAA==.Grimroxs:BAAANQAECgQICgAAAA==.Griptape:BAABNQAECoEaAAMTAAYKpRTyWwBhAQATAAYKpRTyWwBhAQAUAAEKGgJA4wAeAAABNQAECgEIAQADAAAAAA==.',
Gu='Guylapso:BAAANQADCgYIBwAAAA==.',
['Gå']='Gålahad:BAAANQAECgEIAQAAAA==.',
Ha='Hairydragon:BAAANQAECgQIBAABNQAECggIIQASAJYeAA==.Handerbug:BAABNQAECoEmAAMJAAkKQyQQBgCbAwAJAAkKDiQQBgCbAwAVAAEKnCOCQABlAAAAAA==.Handiebug:BAAANQADCgYIBgABNQAECgkJJgAJAEMkAA==.Handybug:BAAANQADCgUICAABNQAECgkJJgAJAEMkAA==.',
He='Healtaxi:BAAANQAECgEIAQAAAA==.Heiler:BAAANQAECgYIEwAAAA==.',
Hi='Hi:BAAANQAECgUICQAAAA==.',
Ho='Hogglethorp:BAAANQAECgIIAgAAAA==.Hokis:BAAANQADCgcIBwAAAA==.Holyhooters:BAAANQADCggIEgAAAA==.Horns:BAAANQADCgYIHAAAAA==.Hornshatter:BAAANQAECgEIAQAAAA==.',
Hr='Hruroth:BAAANQADCgMIBAAAAA==.',
Id='Idontrez:BAAANQAECgEIAQAAAA==.',
Il='Illadron:BAAANQAECgYICQAAAA==.',
In='Inala:BAAANQADCgUIBgAAAA==.Infuzed:BAABNQAECoEgAAIHAAgKehm2JgA+AgAHAAgKehm2JgA+AgAAAA==.',
Io='Iove:BAABNQAECoEWAAIEAAcKoRaeXADbAQAEAAcKoRaeXADbAQAAAA==.',
It='Itsmykitty:BAAANQABCgIIAgABNQADCggIBgADAAAAAA==.',
Ja='Jacksus:BAAANQAECgYIDAAAAA==.',
Jd='Jdbud:BAAANQADCgUICgAAAA==.Jdpot:BAAANQAECgQIBgAAAA==.',
Je='Jenaaidy:BAAANQAECgUICwAAAA==.Jesko:BAAANQADCgUICAAAAA==.',
Jo='Joedavola:BAAANQAECgEJAQAAAA==.Jooshie:BAAANQAECgMIBQABNQAECgkJJAAWAAciAA==.Jooshy:BAABNQAECoEkAAIWAAkKByJHBABlAwAWAAkKByJHBABlAwAAAA==.Josher:BAAANQADCgEIAQABNQAECgkJJAAWAAciAA==.Joshieboba:BAAANQAECggICwABNQAECgkJJAAWAAciAA==.Joyzee:BAAANQADCgcIEQAAAA==.',
Ju='Judge:BAAANQAECggIDgAAAA==.Justviolence:BAAANQADCggIDgAAAA==.',
Jy='Jynrokka:BAAANQAECgQICgAAAA==.',
Ka='Kanati:BAAANQADCgUIBQAAAA==.Katasaria:BAABNQAECoEmAAIPAAkKtyE3IQAlAwAPAAkKtyE3IQAlAwAAAA==.Katiebug:BAAANQADCggIGwAAAA==.Katiekat:BAAANQADCgQIBgAAAA==.Kaycee:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.Kayceedilla:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.Kaycer:BAAANQAECgEIAQAAAA==.',
Ke='Keeps:BAAANQADCgEIAQAAAA==.Kerl:BAAANQADCgYIBgAAAA==.Kestrell:BAAANQAECgQICQAAAA==.Kevoni:BAAANQADCgMIAwAAAA==.',
Kh='Khorlock:BAAANQAECgQIDwAAAA==.Khorus:BAABNQAECoEbAAIXAAcKOhXwlwC9AQAXAAcKOhXwlwC9AQAAAA==.',
Ki='Kirana:BAAANQAECgQICQAAAA==.',
Ko='Koalateectrl:BAAANQADCgUIBQAAAA==.',
Kr='Kravin:BAAANQADCggIIAAAAA==.',
Ku='Kudrani:BAAANQADCgQIBwABNQADCggIEQADAAAAAA==.',
Ky='Kynnas:BAABNQAECoEoAAIIAAkKPw3RIgAUAgAIAAkKPw3RIgAUAgAAAA==.',
La='Laneywine:BAAANQABCgEIAQAAAA==.Larlifax:BAAANQAECgEIAQAAAA==.Lauxy:BAAANQAECgYICAAAAA==.',
Le='Leonuss:BAABNQAECoErAAIPAAkKmyWuBQDCAwAPAAkKmyWuBQDCAwAAAA==.Levìstus:BAAANQAECgQICgAAAA==.Leylaní:BAABNQAECoEbAAIKAAcK7BECgQDbAQAKAAcK7BECgQDbAQAAAA==.',
Li='Lillinth:BAAANQAECgUJCQAAAA==.Lilmagedude:BAAANQAECgIIBAAAAA==.Lilmissblue:BAAANQADCgcIBwAAAA==.Linoir:BAABNQAECoEjAAIXAAkK5h/XLAD3AgAXAAkK5h/XLAD3AgAAAA==.Livenasty:BAAANQAECgUIAwAAAA==.',
Lo='Loroessan:BAAANQADCgIIAgAAAA==.',
Lu='Lucylawladin:BAAANQAECgMIBAAAAA==.',
Ly='Lykios:BAAANQADCgYIBgAAAA==.Lythea:BAAANQAECgUICAABNQAECgkJJgAYAIgeAA==.Lytheum:BAABNQAECoEmAAIYAAkKiB41BgATAwAYAAkKiB41BgATAwAAAA==.',
Ma='Magikon:BAAANQADCgEIAQAAAA==.Magista:BAAANQAECgUIBQAAAA==.Maitias:BAAANQADCgMIAwABNQADCgYIBgADAAAAAA==.Malachar:BAAANQAECgQICgAAAA==.Malboro:BAAANQAECgUIDgAAAA==.Maled:BAAANQAECgUICwAAAA==.',
Me='Meldin:BAAANQAECgUICgAAAA==.Method:BAABNQAECoEmAAMZAAkKDA1eIwCZAQAZAAkKDA1eIwCZAQAXAAEKYAykfwEvAAAAAA==.',
Mi='Miannya:BAABNQAECoEfAAISAAgKgBoRGQBRAgASAAgKgBoRGQBRAgAAAA==.Mignons:BAAANQAECgQIBAAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mineos:BAAANQAECgQIBQAAAA==.Minipedro:BAAANQAECgUICAABNQAECgkJLwAHAMceAA==.Mirmidon:BAAANQABCggIEAAAAA==.Missingparts:BAAANQAECgEIAwAAAA==.Mistamiso:BAAANQAECgMIBAABNQAECggIIAAHAHoZAA==.Mistrmiso:BAAANQADCgEIAQABNQAECggIIAAHAHoZAA==.',
Mo='Moahuntress:BAAANQADCgUICQAAAA==.Moonlyt:BAAANQADCggIGQAAAA==.Morgaine:BAAANQADCgcIHAABNQAECgQIBQADAAAAAA==.Morn:BAABNQAECoEfAAIYAAgKDRm8DgBUAgAYAAgKDRm8DgBUAgAAAA==.',
Mu='Mutalation:BAAANQADCggICAAAAA==.',
My='Myra:BAAANQADCgMIAwAAAA==.Mystu:BAAANQADCgYIBgAAAA==.',
Na='Nadià:BAAANQAECgUICAAAAA==.',
Ne='Needagrip:BAABNQAECoEbAAITAAcKCBQJTACmAQATAAcKCBQJTACmAQAAAA==.Netherid:BAAANQADCgQICAAAAA==.',
Ni='Nidwick:BAAANQADCgIIAgAAAA==.',
No='Notrobo:BAAANQAECgUIBQABNQAECgkJJgAPALchAA==.',
Ny='Nystannia:BAAANQADCgEIAQABNQADCggIEQADAAAAAA==.',
On='Onyx:BAAANQADCgMIAwAAAA==.',
Oo='Oor:BAAANQAECgMIAwABNQAECggIHAACAHweAA==.',
Or='Orialis:BAAANQADCgUIBQAAAA==.Orlandbro:BAABNQAECoEdAAMaAAkKsRmHIAAsAgAaAAgKMRiHIAAsAgAKAAMKjSAF8gDrAAAAAA==.',
Os='Oshiokiyo:BAAANQADCggIJAAAAA==.',
Pa='Patchs:BAAANQAECgEIAQAAAA==.Pawradox:BAAANQAECgYIEgAAAA==.',
Pe='Peeves:BAAANQADCgMIAgABNQAECgkJJgAJAEMkAA==.',
Ph='Phenomenon:BAABNQAECoEnAAIKAAkKHRsdIQD2AgAKAAkKHRsdIQD2AgAAAA==.',
Pl='Plina:BAAANQAECgYIEwAAAA==.',
Po='Ponglenis:BAAANQAECgMIAQABNQAECgUIAwADAAAAAA==.Portalmaster:BAAANQADCgIJAgAAAA==.Poshiesty:BAAANQAECgYIDQAAAA==.Potatofox:BAAANQADCgQIBAAAAA==.Potatolor:BAAANQAECgYIEQAAAA==.',
Pr='Presto:BAAANQADCgMIAwAAAA==.',
Pu='Pulli:BAAANQADCgQIBAAAAA==.Pusinmyboot:BAAANQADCgEIAQAAAA==.',
Pv='Pve:BAABNQAECoEkAAMbAAkKEyPMAACMAwAbAAkKEyPMAACMAwAKAAEKMxGwLQFFAAAAAA==.',
Ra='Raehanji:BAAANQADCgQIBgAAAA==.Raiina:BAABNQAECoEhAAICAAgKgBlDPQBBAgACAAgKgBlDPQBBAgAAAA==.Rains:BAAANQAECgUICgAAAA==.Rathane:BAABNQAECoEtAAIKAAkKgBejSQBpAgAKAAkKgBejSQBpAgAAAA==.Razhj:BAAANQADCgIIAgAAAA==.',
Re='Reapr:BAABNQAECoEbAAIcAAcKBRlILgD3AQAcAAcKBRlILgD3AQAAAA==.Redrabbit:BAAANQAECgIIAgAAAA==.Reikpord:BAAANQADCggICAAAAA==.Rexx:BAAANQADCgYICgAAAA==.',
Rh='Rhapsody:BAAANQAECgQICgAAAA==.',
Ri='Rizzwan:BAAANQAECgEIAQAAAA==.',
Ro='Robotkirky:BAAANQAECgQIBAAAAA==.',
Ru='Runecleaver:BAABNQAECoEcAAICAAgKfB6VJgCqAgACAAgKfB6VJgCqAgAAAA==.Ruw:BAAANQAECgUIDQAAAA==.',
Sa='Sardroth:BAABNQAECoElAAMUAAkKPiTwBwByAwAUAAkKPiTwBwByAwAcAAIK5hPGfABvAAAAAA==.Satavara:BAAANQAECgQICgAAAA==.',
Se='Seiba:BAAANQABCgMIAwAAAA==.',
Sh='Shapòópy:BAAANQAECgQIBwAAAA==.Sharius:BAAANQADCggIBgAAAA==.Shavv:BAAANQADCgQIBgAAAA==.Shawesome:BAAANQADCgYIBgAAAA==.Shiera:BAAANQAECgcIEQAAAA==.Shockyghost:BAAANQABCgMIAwAAAA==.',
Si='Sightlightx:BAAANQAECgQICAAAAA==.Sigs:BAAANQADCgYIBgAAAA==.Silvershine:BAAANQADCggICwAAAA==.Siryn:BAAANQAECgUIBQAAAA==.',
Sl='Slaphaschel:BAAANQADCgMIAwAAAA==.',
Sm='Smallest:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.',
Sp='Sparkelynn:BAAANQADCgQIBgAAAA==.Spinlock:BAAANQADCgQIBAAAAA==.Spitfyre:BAAANQADCggICwAAAA==.',
Sq='Squeeze:BAAANQADCgMJAwAAAA==.',
St='Stonehammer:BAAANQADCgUIBQAAAA==.',
Su='Susa:BAAANQADCgMIBAAAAA==.',
Sy='Sylesta:BAABNQAECoEkAAMLAAkKChB+IQDvAQALAAkKChB+IQDvAQAJAAYKTg85WABKAQAAAA==.Syrden:BAAANQADCggIDAABNQAECgkJJQALACsMAA==.',
Ta='Talís:BAAANQADCggIFwAAAA==.Taranis:BAAANQADCgcIDAAAAA==.',
Te='Teremen:BAAANQADCgUICQABNQAFFAcIDQABAMEaAA==.',
Th='Thandas:BAAANQADCgYIDQAAAA==.Thekarens:BAAANQAECgMIBAAAAA==.Thniper:BAABNQAECoEbAAIaAAgKCRwsGgBrAgAaAAgKCRwsGgBrAgAAAA==.',
Ti='Tiamaria:BAABNQAECoElAAIdAAkK7Q2rTQATAgAdAAkK7Q2rTQATAgAAAA==.',
To='Tomatomasta:BAAANQADCgQIBAAAAA==.',
Tr='Trick:BAAANQADCgYIBgAAAA==.Trilbey:BAAANQADCgYICwAAAA==.Trismegistus:BAAANQADCgYIBgAAAA==.',
Tw='Twittch:BAAANQABCgEIAQAAAA==.',
Ty='Tyinviril:BAACNQAFFIENAAIBAAcKwRrKAQBmAgABAAcKwRrKAQBmAgA1AAQKgTYAAgEACQqIJsQAAOMDAAEACQqIJsQAAOMDAAAA.Tyrandice:BAAANQAECgEIAgABNQAECggIAQADAAAAAA==.Tythoruin:BAAANQAECgMIAwABNQAFFAcIDQABAMEaAA==.Tyvireth:BAAANQADCggIDgABNQAFFAcIDQABAMEaAA==.',
Ve='Veraz:BAABNQAECoEtAAMXAAkKMxtHOADMAgAXAAkKMxtHOADMAgAdAAcKbAzkfQB2AQAAAA==.',
Vo='Vonawesome:BAAANQAECgQIBgAAAA==.Vorpalblade:BAABNQAECoElAAIeAAkKTxKpEADuAQAeAAkKTxKpEADuAQAAAA==.',
Vy='Vylas:BAAANQADCgEIAQAAAA==.Vyraal:BAAANQAECgMIBgAAAA==.',
Wa='Warloque:BAAANQADCgUIEAAAAA==.Warlorok:BAAANQADCgYIBgAAAA==.Warpsmithoor:BAAANQAECgYIBwABNQAECggIHAACAHweAA==.',
We='Wend:BAABNQAECoEnAAIfAAkKWB+iAAAxAwAfAAkKWB+iAAAxAwAAAA==.Weywey:BAAANQAECgQICgAAAA==.',
Wh='Whisperspeak:BAAANQABCgEIAQAAAA==.',
Wo='Wobblerslock:BAAANQADCgQICAABNQADCgcICQADAAAAAA==.',
Wr='Wram:BAAANQAECgQIBQAAAA==.Wreckturd:BAAANQAECgQIBAABNQAECgcIGwAXADoVAA==.Wreckuiem:BAAANQAECgQIBAABNQAECgcIGwAXADoVAA==.',
Wy='Wychlord:BAAANQAECgEIAQAAAA==.Wylder:BAAANQAECgQICAAAAA==.',
Xe='Xenophilious:BAAANQAECgUICQAAAA==.',
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
