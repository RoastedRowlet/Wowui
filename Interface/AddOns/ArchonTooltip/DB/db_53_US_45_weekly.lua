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

local lookup = {'Priest-Shadow','Unknown-Unknown','Priest-Holy','Priest-Discipline','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Unholy','Druid-Guardian','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Frost','Paladin-Holy','Warrior-Protection','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Adaila:BAABNQAECoEXAAIBAAgKSgejLwBVAQABAAgKSgejLwBVAQAAAA==.',
Ai='Aiir:BAAANQAECgMIBAAAAA==.',
Aj='Ajaki:BAAANQADCgMJAwAAAA==.Ajaxstar:BAAANQAECgEJAQAAAA==.',
Al='Alethe:BAAANQAECgcIDgAAAA==.Alfivin:BAAANQAECgEJAQAAAA==.All:BAAANQAECgYIEgAAAA==.Almondor:BAAANQADCgYIBgAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgAAAA==.Ambridgerose:BAAANQADCggIDwAAAA==.Ammariel:BAAANQAECgEIAQAAAA==.',
Ap='Apocalypsus:BAAANQADCgYJDAAAAA==.Appolyin:BAAANQAECgQJBgAAAA==.',
Ar='Arlan:BAAANQADCgIIAgAAAA==.',
As='Ashtomb:BAAANQADCgYIBgABNQAECgYIEQACAAAAAA==.',
At='Athenâ:BAAANQAECgQJCgAAAA==.',
Au='Audarah:BAAANQADCggIDQAAAA==.Audrac:BAAANQADCgEIAQAAAA==.',
Av='Availis:BAAANQADCggIDgAAAA==.Avari:BAAANQADCgMIAwABNQADCggIEQACAAAAAA==.',
Aw='Awawa:BAAANQADCgQIBAAAAA==.',
Az='Azariel:BAABNQAECoEaAAQDAAgKxAVScgBXAQADAAcKjAZScgBXAQAEAAEKSAFBKAAdAAABAAEKzgAIdgAQAAAAAA==.Azorahai:BAAANQAECgQIBAAAAA==.Azshalia:BAAANQAECgMIAwAAAA==.',
Ba='Bacardiand:BAABNQAECoEaAAIFAAgKqxeGDQBWAgAFAAgKqxeGDQBWAgAAAA==.Baishu:BAABNQAECoEZAAMGAAgKshY0KQACAgAGAAcKrxk0KQACAgAHAAEKwwHOXwAhAAAAAA==.Balfazar:BAAANQAECgIIAgAAAA==.Banilibug:BAAANQADCgcIDAAAAA==.Baraddur:BAAANQADCgQIBgAAAA==.Baradun:BAAANQABCgYJCQAAAA==.Barrymanalow:BAAANQAECgUIDQAAAA==.',
Be='Bearclaw:BAAANQADCgUIBQAAAA==.Beorngoat:BAAANQAECgUIBQAAAA==.',
Bl='Blackout:BAAANQAECgIIBAABNQAECggIHAAGAOEXAA==.Bluerabbit:BAAANQADCgYICwABNQAECgkJIAAIADYkAA==.',
Bo='Bobbybrady:BAAANQADCgUICgAAAA==.Bokni:BAAANQADCgYIBgAAAA==.',
Br='Brayk:BAAANQADCgIIAgAAAA==.',
Bu='Bufforc:BAAANQADCgYIBgAAAA==.Buildie:BAAANQADCgcIBwAAAA==.Bushwhacker:BAAANQAECgEJAQAAAA==.Butterbean:BAAANQAECgcIEwAAAA==.',
Ca='Calice:BAAANQADCgMIAwAAAA==.Capziesh:BAAANQADCgUIBgAAAA==.Carch:BAEANQADCgUIBQAAAA==.Catameringue:BAABNQAECoEdAAMJAAgKwCEaCQAFAwAJAAgKwCEaCQAFAwAIAAEK2wWhnwAgAAAAAA==.',
Ch='Chicxulub:BAAANQADCgYIDAAAAA==.Chonkyninja:BAAANQAECgQJBAAAAA==.Choroksaek:BAAANQADCgYIEgAAAA==.',
Cl='Classfantasy:BAABNQAECoEbAAMKAAgKQBTzQwAZAgAKAAgKQBTzQwAZAgALAAUKVwa4pgDMAAAAAA==.',
Co='Cool:BAAANQADCgcIBwABNQAECgQIAgACAAAAAA==.',
Ct='Cthruthyveil:BAAANQAECgIIAgAAAA==.',
Cu='Cursè:BAAANQABCgIIAgABNQADCggIBgACAAAAAA==.',
Cy='Cythrandir:BAAANQADCgQIBQABNQAECggIGwAMAEkaAA==.',
Da='Dany:BAAANQADCgYICwAAAA==.Darkriff:BAAANQABCgMIBwAAAA==.Daruta:BAAANQADCgQIBgAAAA==.Daytona:BAAANQAECgMIBQAAAA==.',
Dd='Ddccssff:BAAANQAECgMIAwAAAA==.',
De='Deathcoiled:BAAANQAECgIIAgAAAA==.Demonx:BAAANQAECgYIEAAAAA==.Dethrahzen:BAAANQAECgEIAgAAAA==.',
Di='Disektor:BAAANQAECgYICgAAAA==.',
Dk='Dkray:BAAANQAECgMICAABNQAECgQIBAACAAAAAA==.',
Do='Donorli:BAAANQADCgYIBgAAAA==.Dotsfordayz:BAAANQAECgEIAwABNQAECgEIAQACAAAAAA==.',
Dr='Dronesworn:BAAANQADCgUICgAAAA==.Drstránge:BAAANQAECgQIBgAAAA==.',
Du='Dugatotems:BAABNQAECoEgAAMLAAgKjhZxTgDZAQALAAgKjhZxTgDZAQAKAAgKtwr4WgDAAQAAAA==.Dunkle:BAABNQAECoEeAAINAAgKIhiYXQAuAgANAAgKIhiYXQAuAgAAAA==.Duskhawk:BAAANQAECgQIBQAAAA==.',
Dy='Dynxy:BAAANQADCgYIBgAAAA==.',
Eb='Ebonise:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
El='Elivien:BAAANQADCgIIAgABNQADCggIEQACAAAAAA==.Ellechero:BAAANQADCggIIwAAAA==.',
Eo='Eogimboonn:BAAANQADCgYIBgAAAA==.',
Er='Eredin:BAAANQADCgMIAwAAAA==.Erinna:BAAANQAECgIIAgAAAA==.Erommêl:BAAANQADCgUJCgAAAA==.',
Fa='Farsha:BAAANQADCgYIBgABNQADCggIEQACAAAAAA==.',
Fe='Fextrius:BAAANQAECgQIBQAAAA==.',
Fr='Frthckr:BAAANQADCgIIAgAAAA==.',
Ga='Gazebo:BAAANQADCgIJAgAAAA==.',
Ge='Genghis:BAAANQAECggIAQAAAA==.',
Gh='Ghast:BAABNQAECoEiAAMOAAgKigwObADCAQAOAAgKEwwObADCAQAPAAIK6ApeVwBmAAAAAA==.',
Gi='Giddley:BAAANQABCgMIAwAAAA==.Gigaflare:BAABNQAECoEfAAMQAAgKbAeeGQDfAAAMAAgKswS91wCGAQAQAAUKhgieGQDfAAAAAA==.',
Gl='Gladîator:BAAANQADCgEJAQAAAA==.Glahmgold:BAAANQAECgQIBAAAAA==.',
Go='Goatale:BAABNQAECoEZAAIRAAcKWRtFGgAYAgARAAcKWRtFGgAYAgAAAA==.Goatseer:BAABNQAECoEZAAIFAAgK2BiBCwCBAgAFAAgK2BiBCwCBAgAAAA==.Goatwizard:BAAANQAECgMIBAAAAA==.Gobblynn:BAAANQADCggIFgAAAA==.Goldvalkyrie:BAAANQADCgUIBQAAAA==.Golokan:BAAANQADCggIEQAAAA==.',
Gr='Grandpawolf:BAAANQAECgIIAwAAAA==.Graymoon:BAAANQADCgQICAAAAA==.Greywings:BAAANQAECgIIAgAAAA==.Grimroxs:BAAANQAECgQIBgAAAA==.Griptape:BAABNQAECoEZAAMSAAYKpRRAUABvAQASAAYKpRRAUABvAQATAAEKGgJSwgAgAAABNQAECgEIAQACAAAAAA==.',
Gu='Guylapso:BAAANQABCgIIBAAAAA==.',
['Gå']='Gålahad:BAAANQAECgEIAQAAAA==.',
Ha='Hairydragon:BAAANQADCgYIBgABNQAECgcIGQARAFkbAA==.Handerbug:BAABNQAECoEgAAMIAAkKNiSIBACoAwAIAAkKAiSIBACoAwAUAAEKnCNuNABmAAAAAA==.Handiebug:BAAANQADCgYIBgABNQAECgkJIAAIADYkAA==.',
He='Healtaxi:BAAANQAECgEIAQAAAA==.Heiler:BAAANQAECgYIDQAAAA==.',
Hi='Hi:BAAANQAECgUICQAAAA==.',
Ho='Hogglethorp:BAAANQAECgIIAgAAAA==.Hokis:BAAANQADCgcIBwAAAA==.Holyhooters:BAAANQADCgUICgAAAA==.Horns:BAAANQADCgUIFQAAAA==.Hornshatter:BAAANQADCgYIBgAAAA==.',
Hr='Hruroth:BAAANQADCgMIBAAAAA==.',
Id='Idontrez:BAAANQAECgEIAQAAAA==.',
Il='Illadron:BAAANQAECgYIBwAAAA==.',
In='Inala:BAAANQADCgUIBgAAAA==.Infuzed:BAABNQAECoEcAAIGAAgK4RfpIwAvAgAGAAgK4RfpIwAvAgAAAA==.',
Io='Iove:BAAANQAECgYIDwAAAA==.',
It='Itsmykitty:BAAANQABCgIIAgABNQADCggIBgACAAAAAA==.',
Ja='Jacksus:BAAANQAECgQIBgAAAA==.',
Jd='Jdbud:BAAANQADCgUICgAAAA==.Jdpot:BAAANQAECgIIAgAAAA==.',
Je='Jenaaidy:BAAANQAECgMIBgAAAA==.Jesko:BAAANQADCgUICAAAAA==.',
Jo='Joedavola:BAAANQAECgEJAQAAAA==.Jooshie:BAAANQAECgIIAwABNQAECggIIAAVAIUiAA==.Jooshy:BAABNQAECoEgAAIVAAgKhSJ5BwARAwAVAAgKhSJ5BwARAwAAAA==.Josher:BAAANQADCgEIAQABNQAECggIIAAVAIUiAA==.Joshieboba:BAAANQAECgIIAwABNQAECggIIAAVAIUiAA==.Joyzee:BAAANQADCgcIEQAAAA==.',
Ju='Judge:BAAANQAECgQIDAAAAA==.Justviolence:BAAANQADCggICAAAAA==.',
Jy='Jynrokka:BAAANQAECgQIBgAAAA==.',
Ka='Kanati:BAAANQADCgUIBQAAAA==.Katasaria:BAABNQAECoEjAAINAAkKsiEQGwAtAwANAAkKsiEQGwAtAwAAAA==.Katiebug:BAAANQADCggIFwAAAA==.Katiekat:BAAANQADCgQIBgAAAA==.Kaycee:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Kayceedilla:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Kaycer:BAAANQAECgEIAQAAAA==.',
Ke='Keeps:BAAANQADCgEIAQAAAA==.Kestrell:BAAANQAECgMIBQAAAA==.Kevoni:BAAANQADCgMIAwAAAA==.',
Kh='Khorlock:BAAANQAECgQIDwAAAA==.Khorus:BAABNQAECoEbAAIWAAcKOhW2fADOAQAWAAcKOhW2fADOAQAAAA==.',
Ki='Kirana:BAAANQAECgQIBQAAAA==.',
Ko='Koalateectrl:BAAANQADCgUIBQAAAA==.',
Kr='Kravin:BAAANQADCggIIAAAAA==.',
Ku='Kudrani:BAAANQADCgQIBwABNQADCggIEQACAAAAAA==.',
Ky='Kynnas:BAABNQAECoEgAAIHAAgKUwpEKADEAQAHAAgKUwpEKADEAQAAAA==.',
La='Laneywine:BAAANQABCgEJAQAAAA==.Larlifax:BAAANQAECgEIAQAAAA==.Lauxy:BAAANQAECgYICAAAAA==.',
Le='Leonuss:BAABNQAECoEoAAINAAkKdSXLAwDOAwANAAkKdSXLAwDOAwAAAA==.Levìstus:BAAANQAECgQIBgAAAA==.Leylaní:BAAANQAECgYIEAAAAA==.',
Li='Lillinth:BAAANQAECgUJCQAAAA==.Lilmagedude:BAAANQAECgIIBAAAAA==.Lilmissblue:BAAANQADCgcIBwAAAA==.Linoir:BAABNQAECoEeAAIWAAgKxB+kNwCsAgAWAAgKxB+kNwCsAgAAAA==.Livenasty:BAAANQAECgQIAgAAAA==.',
Lo='Loroessan:BAAANQADCgIIAgAAAA==.',
Lu='Lucylawladin:BAAANQAECgEJAQAAAA==.',
Ly='Lykios:BAAANQADCgYIBgAAAA==.Lythea:BAAANQAECgUICAABNQAECgkJIAAXAJ0cAA==.Lytheum:BAABNQAECoEgAAIXAAkKnRz7BgDvAgAXAAkKnRz7BgDvAgAAAA==.',
Ma='Magikon:BAAANQADCgEIAQAAAA==.Magista:BAAANQAECgUIBQAAAA==.Malachar:BAAANQAECgQIBgAAAA==.Malboro:BAAANQAECgUICQAAAA==.Maled:BAAANQAECgMIBgAAAA==.',
Me='Meldin:BAAANQAECgUICgAAAA==.Method:BAABNQAECoEgAAMYAAkKqgzDIwBnAQAYAAgKtAzDIwBnAQAWAAEKYAzgSwE0AAAAAA==.',
Mi='Miannya:BAABNQAECoEfAAIRAAgKgBpAFABpAgARAAgKgBpAFABpAgAAAA==.Mignons:BAAANQAECgQIBAAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mineos:BAAANQAECgEIAQAAAA==.Minipedro:BAAANQAECgMIAwABNQAECgkJJwAGALAeAA==.Mirmidon:BAAANQABCggIDgAAAA==.Missingparts:BAAANQAECgEIAgAAAA==.Mistamiso:BAAANQAECgIIAgABNQAECggIHAAGAOEXAA==.Mistrmiso:BAAANQADCgEIAQABNQAECggIHAAGAOEXAA==.',
Mo='Moahuntress:BAAANQADCgUICQAAAA==.Moonlyt:BAAANQADCggIGQAAAA==.Morgaine:BAAANQADCgcIFgABNQAECgMIAwACAAAAAA==.Morn:BAABNQAECoEZAAIXAAgK2hUsEAAXAgAXAAgK2hUsEAAXAgAAAA==.',
My='Myra:BAAANQADCgMIAwAAAA==.Mystu:BAAANQADCgYIBgAAAA==.',
Na='Nadià:BAAANQAECgMIBgAAAA==.',
Ne='Needagrip:BAAANQAECgYIEAAAAA==.Netherid:BAAANQADCgQIBAAAAA==.',
Ni='Nidwick:BAAANQADCgIIAgAAAA==.',
No='Notrobo:BAAANQAECgUIBQABNQAECgkJIwANALIhAA==.',
Ny='Nystannia:BAAANQADCgEIAQABNQADCggIEQACAAAAAA==.',
On='Onyx:BAAANQADCgMIAwAAAA==.',
Oo='Oor:BAAANQAECgMIAwABNQAECgYIEQACAAAAAA==.',
Or='Orialis:BAAANQADCgUIBQAAAA==.Orlandbro:BAABNQAECoEaAAMZAAkKahdvHwAXAgAZAAgKoRVvHwAXAgAaAAMKjSCv0AD1AAAAAA==.',
Os='Oshiokiyo:BAAANQADCggIHwAAAA==.',
Pa='Patchs:BAAANQADCgYJCwAAAA==.Pawradox:BAAANQAECgUIDAAAAA==.',
Ph='Phenomenon:BAABNQAECoEZAAIaAAcKJhkYVgAfAgAaAAcKJhkYVgAfAgAAAA==.',
Pl='Plina:BAAANQAECgYIDQAAAA==.',
Po='Portalmaster:BAAANQADCgIJAgAAAA==.Poshiesty:BAAANQAECgUIBwAAAA==.Potatofox:BAAANQADCgIIAgAAAA==.Potatolor:BAAANQAECgUIDAAAAA==.',
Pr='Presto:BAAANQADCgMIAwAAAA==.',
Pu='Pulli:BAAANQADCgQIBAAAAA==.Pusinmyboot:BAAANQADCgEIAQAAAA==.',
Pv='Pve:BAABNQAECoEhAAMbAAgKZCKmAQApAwAbAAgKZCKmAQApAwAaAAEKMxG7DQFFAAAAAA==.',
Ra='Raehanji:BAAANQADCgQIBgAAAA==.Raiina:BAABNQAECoEZAAILAAgKghd7OgAtAgALAAgKghd7OgAtAgAAAA==.Rains:BAAANQAECgMIBgAAAA==.Rathane:BAABNQAECoEqAAIaAAgKmBiTTAA7AgAaAAgKmBiTTAA7AgAAAA==.Razhj:BAAANQADCgIIAgAAAA==.',
Re='Reapr:BAAANQAECgYIEAAAAA==.Redrabbit:BAAANQAECgIIAgAAAA==.Reikpord:BAAANQADCggICAAAAA==.Rexx:BAAANQADCgYICgAAAA==.',
Rh='Rhapsody:BAAANQAECgQIBgAAAA==.',
Ri='Rizzwan:BAAANQAECgEIAQAAAA==.',
Ro='Robotkirky:BAAANQADCggICAAAAA==.',
Ru='Runecleaver:BAAANQAECgYIEQAAAA==.Ruw:BAAANQAECgUICAAAAA==.',
Sa='Sardroth:BAABNQAECoEfAAMTAAgKCyRODgAcAwATAAgKCyRODgAcAwAcAAIK5hOubQBzAAAAAA==.Satavara:BAAANQAECgQIBgAAAA==.',
Se='Seiba:BAAANQABCgMIAwAAAA==.',
Sh='Shapòópy:BAAANQAECgIIAwAAAA==.Sharius:BAAANQADCggIBgAAAA==.Shavv:BAAANQADCgQIBgAAAA==.Shiera:BAAANQAECgcIEQAAAA==.Shockyghost:BAAANQABCgMIAwAAAA==.',
Si='Sightlightx:BAAANQAECgQIBAAAAA==.Sigs:BAAANQADCgYIBgAAAA==.Silvershine:BAAANQADCggICwAAAA==.Siryn:BAAANQADCgYJEAAAAA==.',
Sl='Slaphaschel:BAAANQADCgMIAwAAAA==.',
Sm='Smallest:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.',
Sp='Sparkelynn:BAAANQADCgQIBgAAAA==.Spinlock:BAAANQADCgQIBAAAAA==.Spitfyre:BAAANQADCggICgAAAA==.',
Sq='Squeeze:BAAANQADCgMJAwAAAA==.',
St='Stonehammer:BAAANQADCgUIBQAAAA==.',
Su='Susa:BAAANQADCgMIBAAAAA==.',
Sy='Sylesta:BAABNQAECoEeAAMJAAkKeQ4MHQDzAQAJAAkKeQ4MHQDzAQAIAAYKTg9wTgBVAQAAAA==.Syrden:BAAANQADCggIDAABNQAECggIHwAJADMLAA==.',
Ta='Talís:BAAANQADCgcIFAAAAA==.Taranis:BAAANQADCgcIBwAAAA==.',
Te='Teremen:BAAANQADCgUICQABNQAFFAYICwABAHwZAA==.',
Th='Thandas:BAAANQADCgYIDQAAAA==.Thekarens:BAAANQAECgEIAQAAAA==.Thniper:BAABNQAECoEbAAIZAAgKCRz3FQB/AgAZAAgKCRz3FQB/AgAAAA==.',
Ti='Tiamaria:BAABNQAECoEfAAIdAAgK1w3WUwDYAQAdAAgK1w3WUwDYAQAAAA==.',
To='Tomatomasta:BAAANQADCgIIAgAAAA==.',
Tr='Trick:BAAANQADCgYIBgAAAA==.Trilbey:BAAANQADCgYICwAAAA==.Trismegistus:BAAANQADCgYIBgAAAA==.',
Tw='Twittch:BAAANQABCgEIAQAAAA==.',
Ty='Tyinviril:BAACNQAFFIELAAIBAAYKfBkzAgAVAgABAAYKfBkzAgAVAgA1AAQKgS8AAgEACQo8JmIBAMcDAAEACQo8JmIBAMcDAAAA.Tyrandice:BAAANQAECgEIAQABNQAECggIAQACAAAAAA==.Tythoruin:BAAANQAECgMIAwABNQAFFAYICwABAHwZAA==.Tyvireth:BAAANQADCggIDgABNQAFFAYICwABAHwZAA==.',
Ve='Veraz:BAABNQAECoEkAAMWAAkKlhmGMgDAAgAWAAkKlhmGMgDAAgAdAAcKbAxUbgB7AQAAAA==.',
Vo='Vonawesome:BAAANQAECgQIBQAAAA==.Vorpalblade:BAABNQAECoEfAAIeAAgKjhPQDwDOAQAeAAgKjhPQDwDOAQAAAA==.',
Vy='Vylas:BAAANQADCgEIAQAAAA==.Vyraal:BAAANQAECgMIAwAAAA==.',
Wa='Warloque:BAAANQADCgUJCwAAAA==.Warlorok:BAAANQADCgYIBgAAAA==.Warpsmithoor:BAAANQAECgYIBwABNQAECgYIEQACAAAAAA==.',
We='Wend:BAABNQAECoEhAAIfAAgKeB/PAADtAgAfAAgKeB/PAADtAgAAAA==.Weywey:BAAANQAECgQIBgAAAA==.',
Wo='Wobblerslock:BAAANQADCgQICAABNQADCgcICQACAAAAAA==.',
Wr='Wram:BAAANQAECgMIAwAAAA==.Wreckturd:BAAANQADCggIEgABNQAECgcIGwAWADoVAA==.Wreckuiem:BAAANQAECgQIBAABNQAECgcIGwAWADoVAA==.',
Wy='Wychlord:BAAANQAECgEIAQAAAA==.Wylder:BAAANQAECgQIBAAAAA==.',
Xe='Xenophilious:BAAANQAECgEIAQAAAA==.',
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
