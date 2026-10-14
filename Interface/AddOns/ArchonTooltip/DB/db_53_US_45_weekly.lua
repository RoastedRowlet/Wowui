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

local lookup = {'Priest-Shadow','Priest-Holy','Druid-Feral','Druid-Balance','Druid-Guardian','Shaman-Restoration','Unknown-Unknown','Priest-Discipline','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Shaman-Elemental','Mage-Arcane','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Paladin-Protection','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Frost','Druid-Restoration','Paladin-Holy','Warrior-Protection','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adaila:BAABNQAECn8eAAIBAAkKHwnbLgCpAQABAAkKHwnbLgCpAQAAAA==.Ade:BAAANQAECgIIAgAAAA==.',
Ai='Aiir:BAAANQAECgUICwAAAA==.',
Aj='Ajaki:BAAANQAECgUIBQAAAA==.Ajaxstar:BAAANQAECgUIBgAAAA==.',
Al='Alethe:BAABNQAECn8fAAICAAkKkRaMOACDAgACAAkKkRaMOACDAgAAAA==.Alfivin:BAAANQAECgUIBgAAAA==.All:BAABNQAECn8bAAQDAAcKyxdaFACyAQAEAAcKQxQwSgC6AQADAAcKahNaFACyAQAFAAIKex9IQwChAAAAAA==.Almondor:BAAANQADCgYIBgAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgAAAA==.Ambridgerose:BAAANQADCggIDwAAAA==.Ammariel:BAAANQAECgQIBQAAAA==.Amyis:BAAANQAECgYIBgAAAA==.',
An='Antiwend:BAAANQAECgQIBwAAAA==.',
Ap='Apocalypsus:BAAANQADCgcIDgAAAA==.Appolyin:BAAANQAECgQJBgAAAA==.',
Ar='Arlan:BAAANQADCgIIAgAAAA==.',
As='Ashtomb:BAAANQADCgYIBgABNQAECggIIwAGAHweAA==.',
At='Ata:BAAANQABCgIIAgAAAA==.Athenâ:BAAANQAECgUICwAAAA==.',
Au='Audarah:BAAANQADCggIFAAAAA==.Audrac:BAAANQADCgEIAQAAAA==.',
Av='Availis:BAAANQADCggIDgAAAA==.Avari:BAAANQADCgMIAwABNQADCggIEQAHAAAAAA==.',
Aw='Awawa:BAAANQADCgQIBAAAAA==.',
Az='Azariel:BAABNQAECn8kAAQCAAkKQQf5fwCTAQACAAgKIAj5fwCTAQAIAAEKSAE9MgAbAAABAAEKAACxkwAPAAAAAA==.Azorahai:BAAANQAECgUIDgAAAA==.Azshalia:BAAANQAECgYICwAAAA==.',
Ba='Bacardiand:BAABNQAECn8dAAIJAAkKuBbsEABYAgAJAAkKuBbsEABYAgAAAA==.Baishu:BAABNQAECn8gAAMKAAkKKhysHACwAgAKAAgKKhysHACwAgALAAEKAACodAAhAAAAAA==.Balfazar:BAAANQAECgQICAAAAA==.Banilibug:BAAANQADCgcIDAAAAA==.Baraddur:BAAANQADCgQIBgAAAA==.Baradun:BAAANQAECgUIBQAAAA==.Barrymanalow:BAABNQAECn8dAAIBAAcKLgh8OwBKAQABAAcKLgh8OwBKAQAAAA==.',
Be='Beachmouse:BAAANQADCgEIAQABNQAECgEJAQAHAAAAAA==.Bearclaw:BAAANQADCgUIBQAAAA==.Beorngoat:BAAANQAECgUIBQAAAA==.',
Bl='Blackout:BAAANQAECgUICgABNQAECgkJJAAKAE4bAA==.Bluerabbit:BAAANQAECgEIAgABNQAECgkJKgAEAIwlAA==.',
Bo='Bobbybrady:BAAANQADCgUICgAAAA==.',
Br='Brayk:BAAANQADCgIIAgAAAA==.',
Bu='Bufforc:BAAANQADCgYIBgAAAA==.Buildie:BAAANQADCgcIBwAAAA==.Bushwhacker:BAAANQAECgYIBgAAAA==.Butterbean:BAABNQAECn8eAAIMAAkKzRvZQACmAgAMAAkKzRvZQACmAgAAAA==.',
Ca='Calice:BAAANQADCgMIAwAAAA==.Capziesh:BAAANQADCgUIBgAAAA==.Carch:BAEANQADCgUIBQAAAA==.',
Ch='Chickenhawk:BAAANQAECgQIBAAAAA==.Chicxulub:BAAANQADCgYIDAAAAA==.Chonkyninja:BAAANQAECgQJBAAAAA==.Choroksaek:BAAANQADCggIGgAAAA==.',
Ci='Citan:BAAANQADCgUIBQAAAA==.',
Cl='Classfantasy:BAABNQAECn8lAAMNAAkKLBccSABSAgANAAkKLBccSABSAgAGAAUKVwY+zgDGAAAAAA==.',
Co='Condesate:BAAANQAECgcIBwAAAA==.Cool:BAAANQADCgcIBwABNQAECgUIBQAHAAAAAA==.',
Cr='Crazytoe:BAAANQAECgEIAQAAAA==.Croghon:BAAANQAECgIIAgAAAA==.',
Ct='Cthruthyveil:BAAANQAECgQICgAAAA==.',
Cu='Cursè:BAAANQABCgIIAgABNQADCggIBgAHAAAAAA==.',
Cy='Cythrandir:BAAANQADCgUIDAABNQAECgkJIgAOAIEbAA==.',
Da='Dany:BAAANQADCgYICwAAAA==.Darkriff:BAAANQABCggIDQAAAA==.Daruta:BAAANQADCgQIBgAAAA==.Daytona:BAAANQAECgUIDgAAAA==.',
Dd='Ddccssff:BAAANQAECgYICwAAAA==.',
De='Deathcoiled:BAAANQAECgIIAgAAAA==.Dethrahzen:BAAANQAECgEIAgAAAA==.',
Di='Dindunuthin:BAAANQAECgMIAwAAAA==.Dipika:BAAANQAECgQIBAAAAA==.Disektor:BAABNQAECn8ZAAIPAAcKWRc3igD+AQAPAAcKWRc3igD+AQAAAA==.',
Dk='Dkray:BAAANQAECgUIEAAAAA==.',
Do='Donnettlen:BAAANQADCgcIBwAAAA==.Donorli:BAAANQADCgYIBgAAAA==.Dotsfordayz:BAAANQAECgEIAwABNQAECgEIAQAHAAAAAA==.Douglit:BAAANQAECgQIBAAAAA==.',
Dr='Dronesworn:BAAANQADCgUICgAAAA==.Drstránge:BAAANQAECgQIBgAAAA==.',
Du='Dugatotems:BAABNQAECn8kAAMGAAgKjhZ4awDFAQAGAAgKjhZ4awDFAQANAAgKbQr5dwC2AQAAAA==.Dunkle:BAABNQAECn8oAAIPAAkKLBzsTwCWAgAPAAkKLBzsTwCWAgAAAA==.Duskhawk:BAAANQAECgUIDgAAAA==.',
Dy='Dynxy:BAAANQADCgYIBgAAAA==.',
Eb='Ebonise:BAAANQADCgcIBwABNQAECgQICgAHAAAAAA==.',
Ed='Edrelang:BAAANQADCgMIAgAAAA==.',
El='Elivien:BAAANQADCgIIAgABNQADCggIEQAHAAAAAA==.',
Eo='Eogimboonn:BAAANQADCgYIBgAAAA==.',
Er='Eredin:BAAANQADCgMIAwAAAA==.Erinna:BAAANQAECgIIAgAAAA==.Erommêl:BAAANQAECgQIBAAAAA==.',
Fa='Farsha:BAAANQADCgYIBgABNQADCggIEQAHAAAAAA==.',
Fe='Fextrius:BAAANQAECgYIDwAAAA==.',
Fr='Frthckr:BAAANQADCgIIAgAAAA==.',
Ga='Gazebo:BAAANQADCgIJAgAAAA==.',
Ge='Genghis:BAAANQAECggIAgAAAA==.',
Gh='Ghast:BAABNQAECn84AAMQAAgKoQ9/hADWAQAQAAgKAw9/hADWAQARAAIKqRNdYABjAAAAAA==.',
Gi='Giddley:BAAANQABCgMIAwAAAA==.Gigaflare:BAABNQAECn8pAAMSAAkKVwxqEQCMAQASAAcK0A9qEQCMAQAOAAgKHwVPCgF4AQAAAA==.',
Gl='Gladîator:BAAANQADCgEJAQAAAA==.Glahmgold:BAAANQAECgQIBAAAAA==.',
Go='Goatale:BAABNQAECn8oAAITAAgKuh6XFACtAgATAAgKuh6XFACtAgAAAA==.Goatseer:BAABNQAECn8ZAAIJAAgKQhgGEgBHAgAJAAgKQhgGEgBHAgAAAA==.Goatwizard:BAAANQAECgMIBAAAAA==.Gobblynn:BAAANQADCggIFgAAAA==.Goldvalkyrie:BAAANQADCgUIBQAAAA==.Golokan:BAAANQADCggIEQAAAA==.',
Gr='Grandpawolf:BAAANQAECgUIBgAAAA==.Graymoon:BAAANQADCgQICAAAAA==.Greywings:BAAANQAECgQIBwAAAA==.Grimroxs:BAAANQAECgUIDwAAAA==.Griptape:BAABNQAECn8bAAMUAAcK2BFjWQCKAQAUAAcK2BFjWQCKAQAVAAEKAACo9gAeAAABNQAECgEIAQAHAAAAAA==.',
Gu='Guylapso:BAAANQADCgYIDQAAAA==.',
['Gå']='Gålahad:BAAANQAECgEIAQAAAA==.',
Ha='Hairydragon:BAAANQAECgQIBAABNQAECggIKAATALoeAA==.Handerbug:BAABNQAECn8qAAMEAAkKjCXuAgDOAwAEAAkKjCXuAgDOAwAFAAEKAADfTQBkAAAAAA==.Handiebug:BAAANQADCgYIBgABNQAECgkJKgAEAIwlAA==.Handybug:BAAANQADCgYICQABNQAECgkJKgAEAIwlAA==.',
He='Healtaxi:BAAANQAECgEIAQAAAA==.Heiler:BAABNQAECn8eAAICAAgKlAUsjQBqAQACAAgKlAUsjQBqAQAAAA==.',
Hi='Hi:BAAANQAECgUICQAAAA==.',
Ho='Hogglethorp:BAAANQAECgIIAgAAAA==.Hokis:BAAANQADCgcIBwAAAA==.Holyhooters:BAAANQADCggIEwAAAA==.Horns:BAAANQADCgYIHAAAAA==.Hornshatter:BAAANQAECgQIBwAAAA==.',
Hr='Hruroth:BAAANQADCgMIBAAAAA==.',
Ib='Ibis:BAAANQADCgUIBQAAAA==.',
Id='Idontrez:BAAANQAECgEIAQAAAA==.',
Il='Illadron:BAAANQAECggIDAAAAA==.',
In='Inala:BAAANQAECgQIBAAAAA==.Infuzed:BAABNQAECn8kAAIKAAkKThsDGwC+AgAKAAkKThsDGwC+AgAAAA==.',
Io='Iove:BAABNQAECn8WAAICAAcKoRYybADVAQACAAcKoRYybADVAQAAAA==.',
Ir='Ironface:BAAANQADCgQIBAAAAA==.',
It='Itsmykitty:BAAANQABCgIIAgABNQADCggIBgAHAAAAAA==.',
Ja='Jacksus:BAAANQAECgYIEAABNQAECgkJLgAPAFglAA==.',
Jd='Jdbud:BAAANQADCgUICgAAAA==.Jdpot:BAAANQAECgQICgAAAA==.',
Je='Jenaaidy:BAAANQAECgYIEAAAAA==.Jesko:BAAANQADCgUICAAAAA==.',
Jo='Joedavola:BAAANQAECgQIBQAAAA==.Jooshie:BAAANQAECgMIBgABNQAECgkJJAAWAAciAA==.Jooshy:BAABNQAECn8kAAIWAAkKByL2BABdAwAWAAkKByL2BABdAwAAAA==.Josher:BAAANQADCgEIAQABNQAECgkJJAAWAAciAA==.Joshieboba:BAAANQAECggIDwABNQAECgkJJAAWAAciAA==.Joyzee:BAAANQADCgcIEQAAAA==.',
Ju='Judge:BAAANQAECggIEgAAAA==.Justviolence:BAAANQADCggIDwAAAA==.',
Jy='Jynrokka:BAAANQAECgYIEAAAAA==.',
Ka='Kanati:BAAANQADCgUIBQAAAA==.Katasaria:BAACNQAFFH8GAAIPAAMKkQ71JADTAAAPAAMKkQ71JADTAAA1AAQKfykAAg8ACQq+IcEnABgDAA8ACQq+IcEnABgDAAAA.Katiebug:BAAANQADCggIGwAAAA==.Katiekat:BAAANQADCgQIBgAAAA==.Kaycee:BAAANQADCgEIAQABNQAECgEIAQAHAAAAAA==.Kayceedilla:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Kaycer:BAAANQAECgEIAQAAAA==.',
Ke='Keeps:BAAANQADCgEIAQAAAA==.Kerl:BAAANQADCgYIBgAAAA==.Kestrell:BAAANQAECgcIDwAAAA==.Kevoni:BAAANQADCgMIAwAAAA==.',
Kh='Khorlock:BAAANQAECgQIDwAAAA==.Khorus:BAABNQAECn8bAAIXAAcKixWLtQCtAQAXAAcKixWLtQCtAQAAAA==.',
Ki='Kirana:BAAANQAECgQIDAAAAA==.',
Ko='Koalateectrl:BAAANQADCgUIBQAAAA==.',
Kr='Kravin:BAAANQAECgMIAwAAAA==.',
Ku='Kudrani:BAAANQADCgQIBwABNQADCggIEQAHAAAAAA==.',
Ky='Kynnas:BAABNQAECn8xAAILAAkKLREQIQBBAgALAAkKLREQIQBBAgAAAA==.',
La='Laneywine:BAAANQABCgEIAQAAAA==.Larlifax:BAAANQAECgEIAQAAAA==.Lauxy:BAAANQAECgYICAAAAA==.',
Le='Leonuss:BAABNQAECn8uAAIPAAkKWCWNCACuAwAPAAkKWCWNCACuAwAAAA==.Levìstus:BAAANQAECgQICgAAAA==.Leylaní:BAABNQAECn8iAAIMAAgKMhMMdAAlAgAMAAgKMhMMdAAlAgAAAA==.',
Li='Lidria:BAAANQADCgUIBQAAAA==.Lillinth:BAAANQAECgUJCQAAAA==.Lilmagedude:BAAANQAECgIIBAAAAA==.Lilmissblue:BAAANQADCgcIBwAAAA==.Linoir:BAABNQAECn8nAAIXAAkKpyDKKQAdAwAXAAkKpyDKKQAdAwAAAA==.Livenasty:BAAANQAECgUIBQAAAA==.',
Lo='Loroessan:BAAANQADCgIIAgAAAA==.',
Lu='Lucylawladin:BAAANQAECgMIBAAAAA==.Lurry:BAAANQADCgQIBAAAAA==.',
Ly='Lykios:BAAANQADCgYIBgAAAA==.Lythea:BAAANQAECgUICAABNQAECgkJLQAYAAYgAA==.Lytheum:BAABNQAECn8tAAIYAAkKBiBdBABVAwAYAAkKBiBdBABVAwAAAA==.',
Ma='Maatato:BAAANQADCgQIBAAAAA==.Magikon:BAAANQADCgEIAQAAAA==.Magista:BAAANQAECgUIBQAAAA==.Maitias:BAAANQADCgMIAwABNQADCggIDgAHAAAAAA==.Malachar:BAAANQAECgYIEAAAAA==.Malboro:BAABNQAECn8XAAIRAAgKTQyyFADHAQARAAgKTQyyFADHAQAAAA==.Maled:BAAANQAECgYIEAAAAA==.',
Me='Meldin:BAAANQAECgUIDAAAAA==.Method:BAABNQAECn8qAAMZAAkKuA74JQCsAQAZAAkKuA74JQCsAQAXAAEKYAxzrAEuAAAAAA==.',
Mi='Miannya:BAABNQAECn8jAAITAAkKrBvlFQCeAgATAAkKrBvlFQCeAgAAAA==.Mignons:BAAANQAECgQIBAAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mineos:BAAANQAECgQIBwAAAA==.Minipedro:BAAANQAECgUICAABNQAFFAMIBwAKAJ8RAA==.Mirmidon:BAAANQABCggIEgAAAA==.Missingparts:BAAANQAECgQIBgAAAA==.Mistamiso:BAAANQAECgUICAABNQAECgkJJAAKAE4bAA==.Mistrmiso:BAAANQADCgEIAQABNQAECgkJJAAKAE4bAA==.',
Mm='Mmandalorian:BAAANQADCgQIBAAAAA==.',
Mo='Moahuntress:BAAANQADCgUICQAAAA==.Moonlyt:BAAANQADCggIGQAAAA==.Morgaine:BAAANQADCgcIHAABNQAECgUIBgAHAAAAAA==.Morn:BAABNQAECn8hAAIYAAgKERq4EABIAgAYAAgKERq4EABIAgAAAA==.',
Mu='Mutalation:BAAANQADCggICAAAAA==.',
My='Myra:BAAANQADCgMIAwAAAA==.Mystu:BAAANQADCgYIBgAAAA==.',
Na='Nadià:BAAANQAECgYIDQAAAA==.',
Ne='Needagrip:BAABNQAECn8iAAIUAAgKURY/QAD7AQAUAAgKURY/QAD7AQAAAA==.Netherid:BAAANQADCgQIBgAAAA==.',
Ni='Nidwick:BAAANQADCgIIAgAAAA==.Nifin:BAAANQAECgMIAwAAAA==.',
No='Notrobo:BAAANQAECgUIBQABNQAFFAMIBgAPAJEOAA==.',
Ny='Nystannia:BAAANQADCgEIAQABNQADCggIEQAHAAAAAA==.',
On='Onyx:BAAANQADCgMIAwAAAA==.',
Oo='Oor:BAAANQAECgMIAwABNQAECggIIwAGAHweAA==.',
Or='Orialis:BAAANQADCgUIBQAAAA==.Orlandbro:BAABNQAECn8hAAMaAAkKCxvtHwBNAgAaAAgKvhntHwBNAgAMAAMKoh5KDAHnAAAAAA==.',
Os='Oshiokiyo:BAAANQADCggILAAAAA==.',
Pa='Patchs:BAAANQAECgYIBgAAAA==.Pawradox:BAABNQAECn8fAAIBAAgKZhZrIgAdAgABAAgKZhZrIgAdAgAAAA==.',
Pe='Peeves:BAAANQADCgMIAgABNQAECgkJKgAEAIwlAA==.',
Ph='Phenomenon:BAABNQAECn8wAAIMAAkKmRv2HwAWAwAMAAkKmRv2HwAWAwAAAA==.',
Pi='Pitviper:BAAANQADCgIIAgAAAA==.',
Pl='Plina:BAABNQAECn8fAAIXAAgKERMmoQDaAQAXAAgKERMmoQDaAQAAAA==.',
Po='Ponglenis:BAAANQAECgMIAwABNQAECgUIBQAHAAAAAA==.Portalmaster:BAAANQADCgIJAgAAAA==.Poshiesty:BAAANQAECggIEgAAAA==.Potatofox:BAAANQADCgQIBAAAAA==.Potatolor:BAAANQAECgYIEQAAAA==.',
Pr='Presto:BAAANQADCgMIAwAAAA==.',
Pu='Pulli:BAAANQADCgQIBAAAAA==.Pusinmyboot:BAAANQADCgEIAQAAAA==.',
Pv='Pve:BAABNQAECn8rAAMbAAkKWSPNAACSAwAbAAkKWSPNAACSAwAMAAEKMxEgSgFEAAAAAA==.',
Py='Pyx:BAAANQAECgQIBAAAAA==.',
Ra='Raehanji:BAAANQADCgQIBgAAAA==.Raiina:BAABNQAECn8lAAIGAAkKehigOAB6AgAGAAkKehigOAB6AgAAAA==.Rains:BAAANQAECgYIDwAAAA==.Rathane:BAABNQAECn82AAIMAAkKABgcUQB6AgAMAAkKABgcUQB6AgAAAA==.Razhj:BAAANQADCgIIAgAAAA==.',
Re='Reapr:BAABNQAECn8iAAIcAAgKHxlNMAAeAgAcAAgKHxlNMAAeAgAAAA==.Redrabbit:BAAANQAECgIIAgAAAA==.Reikpord:BAAANQADCggICAAAAA==.Rexx:BAAANQADCgYICgAAAA==.',
Rh='Rhapsody:BAAANQAECgYIEAAAAA==.',
Ri='Rizzwan:BAAANQAECgQIBQAAAA==.',
Ro='Robotkirky:BAAANQAECgQIBAAAAA==.',
Ru='Runecleaver:BAABNQAECn8jAAIGAAgKfB7jLwCfAgAGAAgKfB7jLwCfAgAAAA==.Ruw:BAAANQAECgYIEwAAAA==.',
Sa='Sardroth:BAABNQAECn8pAAMVAAkK4iRECQB0AwAVAAkK4iRECQB0AwAcAAIK5hN8kgBqAAAAAA==.Satavara:BAAANQAECgQICgAAAA==.',
Se='Seiba:BAAANQABCgMIAwAAAA==.',
Sh='Shapòópy:BAAANQAECgQIBwAAAA==.Sharius:BAAANQADCggIBgAAAA==.Shavv:BAAANQADCgQIBgAAAA==.Shawesome:BAAANQADCgYIBgAAAA==.Shiera:BAAANQAECggIEgAAAA==.Shockyghost:BAAANQADCggICAAAAA==.',
Si='Sightlightx:BAAANQAECgQIDAAAAA==.Sigs:BAAANQADCgYIBgAAAA==.Silvershine:BAAANQADCggICwAAAA==.Siryn:BAAANQAECgYICgAAAA==.',
Sl='Slaphaschel:BAAANQADCgMIAwAAAA==.',
Sm='Smallest:BAAANQADCgEIAQABNQAECgEIAQAHAAAAAA==.',
Sp='Sparkelynn:BAAANQADCgQIBgAAAA==.Spinlock:BAAANQADCgQIBAAAAA==.Spitfyre:BAAANQADCggICwAAAA==.',
Sq='Squeeze:BAAANQADCgMJAwAAAA==.',
St='Stonehammer:BAAANQADCgUIBQAAAA==.',
Su='Susa:BAAANQADCgMIBAAAAA==.',
Sy='Sylesta:BAABNQAECn8nAAMdAAkKChDSJwDeAQAdAAkKChDSJwDeAQAEAAYKdhEeYQBGAQAAAA==.Syrden:BAAANQADCggIDAABNQAECgkJKQAdAHEMAA==.',
Ta='Talís:BAAANQADCggIHwAAAA==.Taranis:BAAANQAECgYIBgAAAA==.',
Te='Teremen:BAAANQADCgUICQABNQAFFAcIDgABAFUYAA==.',
Th='Thandas:BAAANQADCgYIDQAAAA==.Theherooz:BAAANQAECgQIBAAAAA==.Thekarens:BAAANQAECgMIBQAAAA==.Thniper:BAABNQAECn8iAAIaAAgKqxyPGgB+AgAaAAgKqxyPGgB+AgAAAA==.Thoriumaster:BAAANQADCgEIAQAAAA==.',
Ti='Tiamaria:BAABNQAECn8pAAIeAAkK2w4BWgAIAgAeAAkK2w4BWgAIAgAAAA==.',
Tr='Trick:BAAANQADCgYIBgAAAA==.Trilbey:BAAANQADCgYICwAAAA==.Trismegistus:BAAANQADCgcICgAAAA==.',
Tw='Twittch:BAAANQABCgEIAQAAAA==.',
Ty='Tyinviril:BAACNQAFFH8OAAIBAAcKVRhJAgBsAgABAAcKVRhJAgBsAgA1AAQKfzwAAgEACQp4JgQBAOEDAAEACQp4JgQBAOEDAAAA.Tyrandice:BAAANQAECgEIAwABNQAECggIAwAHAAAAAA==.Tythoruin:BAAANQAECgMIAwABNQAFFAcIDgABAFUYAA==.Tyvireth:BAAANQADCggIDgABNQAFFAcIDgABAFUYAA==.',
Ve='Veraz:BAABNQAECn82AAMXAAkKcx87LQAQAwAXAAkKcx87LQAQAwAeAAcKbAwqjgBvAQAAAA==.',
Vo='Vonawesome:BAAANQAECgYIDAAAAA==.Vorpalblade:BAABNQAECn8pAAIfAAkKaRKBEgD6AQAfAAkKaRKBEgD6AQAAAA==.',
Vy='Vylas:BAAANQADCgEIAQAAAA==.Vyraal:BAAANQAECgYICwAAAA==.',
Wa='Warloque:BAAANQADCgUIEAAAAA==.Warlorok:BAAANQADCgYIBgAAAA==.Warpsmithoor:BAAANQAECgYIBwABNQAECggIIwAGAHweAA==.',
We='Wend:BAABNQAECn8rAAIgAAkKfx7GAAAwAwAgAAkKfx7GAAAwAwAAAA==.Weywey:BAAANQAECgYIEAAAAA==.',
Wh='Whisperspeak:BAAANQABCgEIAQAAAA==.',
Wo='Wobblerslock:BAAANQADCgQICAABNQADCgcICQAHAAAAAA==.',
Wr='Wram:BAAANQAECgUIBgAAAA==.Wreckamma:BAAANQAECgQIBAABNQAECgcIGwAXAIsVAA==.Wreckturd:BAAANQAECgQIBAABNQAECgcIGwAXAIsVAA==.Wreckuiem:BAAANQAECgQIBAABNQAECgcIGwAXAIsVAA==.',
Wy='Wychlord:BAAANQAECgEIAQAAAA==.Wylder:BAAANQAECgQIDAAAAA==.',
Xe='Xenophilious:BAAANQAECgUIDwAAAA==.',
Xi='Xiomara:BAAANQADCgQIBgAAAA==.Xiøn:BAAANQAECgIIAgAAAA==.',
Yn='Yn:BAAANQADCgIIAgAAAA==.',
Ze='Zelios:BAAANQADCgYIBgAAAA==.',
Zo='Zoinx:BAABNQAECn8iAAIQAAcK0yC0QACNAgAQAAcK0yC0QACNAgAAAA==.',
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
