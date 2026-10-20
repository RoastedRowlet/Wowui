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

local lookup = {'Priest-Shadow','Paladin-Retribution','Priest-Holy','Druid-Feral','Druid-Balance','Druid-Guardian','Shaman-Restoration','Unknown-Unknown','Priest-Discipline','DeathKnight-Unholy','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Shaman-Elemental','Mage-Arcane','Warrior-Arms','DeathKnight-Blood','Hunter-Marksmanship','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Monk-Windwalker','Druid-Restoration','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warrior-Protection','Warlock-Affliction','Paladin-Protection','Monk-Mistweaver','Hunter-Survival','DeathKnight-Frost','Paladin-Holy','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adaila:BAABNQAECn8eAAIBAAkKHwlULwCpAQABAAkKHwlULwCpAQAAAA==.Ade:BAAANQAECgIIAwAAAA==.',
Ai='Aiir:BAABNQAECn8VAAICAAcKvQh1ZwD2AAACAAcKvQh1ZwD2AAAAAA==.',
Aj='Ajaki:BAAANQAECgUIBQAAAA==.Ajaxstar:BAAANQAECgUIBwAAAA==.',
Al='Alethe:BAABNQAECn8mAAIDAAoKIBYtEwDaAQADAAoKIBYtEwDaAQAAAA==.Alfivin:BAAANQAECgUICAAAAA==.All:BAABNQAECn8bAAQEAAcKyxe/FACwAQAFAAcKQxTrSgC6AQAEAAcKahO/FACwAQAGAAIKex+pRAChAAAAAA==.Almondor:BAAANQADCgYIBgAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgAAAA==.Ambridgerose:BAAANQADCggIEAAAAA==.Ammariel:BAAANQAECgQIBQAAAA==.Amyis:BAAANQAECgYIBwAAAA==.',
An='Antiwend:BAAANQAECgcIDgAAAA==.',
Ap='Apocalypsus:BAAANQADCgcIDwAAAA==.Appolyin:BAAANQAECgQJBgAAAA==.',
Ar='Arlan:BAAANQADCgIIAwAAAA==.',
As='Ashtomb:BAAANQADCgYIBwABNQAECgoKJQAHAHsdAA==.',
At='Ata:BAAANQAECgQIAgAAAA==.Athenâ:BAAANQAECgYICwAAAA==.',
Au='Audrac:BAAANQADCgEIAQAAAA==.',
Av='Availis:BAAANQADCggIEAAAAA==.Avari:BAAANQADCgMIAwABNQADCgYIBwAIAAAAAA==.',
Aw='Awawa:BAAANQADCgQIBAAAAA==.',
Az='Azariel:BAABNQAECn8kAAQDAAkKQQdfgQCTAQADAAgKIAhfgQCTAQAJAAEKSAHXMgAbAAABAAEKAACslQAPAAAAAA==.Azorahai:BAABNQAECn8VAAIKAAYKuAnrhQAJAQAKAAYKuAnrhQAJAQAAAA==.Azshalia:BAAANQAECgYICwAAAA==.',
Ba='Bacardiand:BAABNQAECn8dAAILAAkKuBYYEQBYAgALAAkKuBYYEQBYAgAAAA==.Baishu:BAABNQAECn8iAAMMAAoKCxs3HQCwAgAMAAkKCxs3HQCwAgANAAEKAACOdgAhAAAAAA==.Balfazar:BAAANQAECgYIDAAAAA==.Banilibug:BAAANQADCgcIDgAAAA==.Baraddur:BAAANQADCgQIBwAAAA==.Baradun:BAAANQAECgUIBwAAAA==.Barrymanalow:BAABNQAECn8kAAIBAAgKxAfTFgDRAAABAAgKxAfTFgDRAAAAAA==.Bashaba:BAAANQADCgEIAQAAAA==.',
Be='Beachmouse:BAAANQADCgYIBgABNQAECgEJAQAIAAAAAA==.Bearclaw:BAAANQADCgUIBgAAAA==.Beorngoat:BAAANQAECgYICwAAAA==.Bernarn:BAAANQADCgQIBAAAAA==.',
Bl='Blackout:BAAANQAECgYIDAABNQAECgoKKgAMAE8aAA==.Bloodpool:BAAANQADCgEIAQAAAA==.Bluerabbit:BAAANQAECgEIAgABNQAECgkJKgAFAIwlAA==.',
Bo='Bobbybrady:BAAANQADCgUICwAAAA==.Bokni:BAAANQAECgMIAgAAAA==.',
Br='Bro:BAAANQADCgEIAQAAAA==.',
Bu='Bufforc:BAAANQADCgYIBgAAAA==.Buildie:BAAANQADCgcIBwAAAA==.Bushwhacker:BAAANQAECgYIBwAAAA==.Butterbean:BAABNQAECn8eAAIOAAkKzRu/QQClAgAOAAkKzRu/QQClAgAAAA==.',
Ca='Cahrbon:BAAANQADCgEIAgAAAA==.Calice:BAAANQADCgMIAwAAAA==.Capziesh:BAAANQADCgUIBgAAAA==.Carch:BAEANQADCgUIBQAAAA==.',
Ch='Chickenhawk:BAAANQAECgQICAAAAA==.Chicxulub:BAAANQADCgcIDQAAAA==.Chonkyninja:BAAANQAECgQJBAAAAA==.Choroksaek:BAAANQADCggIIAAAAA==.',
Ci='Citan:BAAANQAECgUIBgAAAA==.',
Cl='Classfantasy:BAABNQAECn8lAAMPAAkKLBcQSQBSAgAPAAkKLBcQSQBSAgAHAAUKVwZ40ADGAAAAAA==.',
Co='Condesate:BAAANQAECgcIBwAAAA==.Condge:BAAANQAECgEIAQAAAA==.Cool:BAAANQADCgcIBwABNQAECgUIBwAIAAAAAA==.',
Cr='Crazytoe:BAAANQAECgEIAgAAAA==.Croghon:BAAANQAECgIIAgAAAA==.',
Ct='Cthruthyveil:BAAANQAECgQIDgAAAA==.',
Cu='Cursè:BAAANQADCgEIAwABNQADCggIBwAIAAAAAA==.',
Cy='Cythrandir:BAAANQAECgEIAQABNQAECgoKJgAQAGgaAA==.',
Da='Dalhia:BAAANQAECgEIAQAAAA==.Dany:BAAANQADCgYICwAAAA==.Darkriff:BAAANQADCgEIAQAAAA==.Daruta:BAAANQADCgQICAAAAA==.Daytona:BAAANQAECgcIDwAAAA==.',
Dd='Ddccssff:BAAANQAECgUIDAAAAA==.',
De='Deathcoiled:BAAANQAECgIIAgAAAA==.Dethrahzen:BAAANQAECgEIAgAAAA==.',
Di='Dindunuthin:BAAANQAECgMIAwAAAA==.Dipika:BAAANQAECgQIBAAAAA==.Disciplina:BAAANQADCgEIAgAAAA==.Disektor:BAABNQAECn8bAAIRAAgK8BUrjAD+AQARAAgK8BUrjAD+AQAAAA==.Diègo:BAAANQADCgEIAQAAAA==.',
Dk='Dkray:BAABNQAECn8XAAMSAAYKuQZ+QQB1AAAKAAUKVAW3nADEAAASAAUK6gV+QQB1AAAAAA==.',
Do='Donnettlen:BAAANQADCgcIBwAAAA==.Donorli:BAAANQADCgYIBgAAAA==.Dotsfordayz:BAAANQAECgEIAwABNQAECgEIAQAIAAAAAA==.Douglit:BAAANQAECgQIBAAAAA==.',
Dr='Dronesworn:BAAANQADCgUIDAAAAA==.Drstránge:BAAANQAECgQIBgAAAA==.',
Du='Dugatotems:BAABNQAECn8oAAMHAAoKnRWybADFAQAHAAoKnRWybADFAQAPAAgKbQqueQC1AQAAAA==.Dunkle:BAABNQAECn8oAAIRAAkKLBz/UACXAgARAAkKLBz/UACXAgAAAA==.Duskhawk:BAABNQAECn8YAAMOAAcKEQU+XwDtAAAOAAcKEQU+XwDtAAATAAIKWwE/gQBBAAAAAA==.',
Dy='Dynxy:BAAANQADCgYIBgAAAA==.',
Eb='Ebonise:BAAANQAECgQIBAABNQAECgQIDgAIAAAAAA==.',
Ed='Edrelang:BAAANQADCgMIAgAAAA==.',
El='Elivien:BAAANQADCgIIBAABNQADCgYIBwAIAAAAAA==.Ellechero:BAAANQAECgIIAQAAAA==.Elsafan:BAAANQADCgEIAQAAAA==.',
Eo='Eogimboonn:BAAANQADCgYIBgAAAA==.',
Er='Eredin:BAAANQADCgMIAwAAAA==.Erinna:BAAANQAECgIIAgAAAA==.Erommêl:BAAANQAECgQIBAAAAA==.',
Fa='Farsha:BAAANQADCgYIBwAAAA==.',
Fe='Fextrius:BAABNQAECn8aAAIRAAgKHBcfFgCwAQARAAgKHBcfFgCwAQAAAA==.',
Fr='Franman:BAAANQAECgEIAQABNQAECgoKNQAUAPgaAA==.Frostpine:BAAANQADCgEIAgAAAA==.Frthckr:BAAANQADCgIIAgAAAA==.',
Ga='Garreux:BAAANQADCgIIAQAAAA==.Gazebo:BAAANQADCgUICAAAAA==.',
Ge='Genghis:BAAANQAECggIAgAAAA==.',
Gh='Ghast:BAABNQAECn86AAMVAAgKQhB6hgDWAQAVAAgKpQ96hgDWAQAWAAIKqRPlYABjAAAAAA==.',
Gi='Giddley:BAAANQADCgEIAQAAAA==.Gigaflare:BAABNQAECn8pAAMXAAkKVwygEQCMAQAXAAcK0A+gEQCMAQAQAAgKHwXZDAF3AQAAAA==.',
Gl='Gladîator:BAAANQADCgEJAQAAAA==.Glahmgold:BAAANQAECgQIBAAAAA==.',
Go='Goatale:BAABNQAECn8sAAIYAAkKAhzzFACtAgAYAAkKAhzzFACtAgAAAA==.Goatseer:BAABNQAECn8ZAAILAAgKQhg8EgBGAgALAAgKQhg8EgBGAgAAAA==.Goatwizard:BAAANQAECgMIBAAAAA==.Gobblynn:BAAANQADCggIFgAAAA==.Goldvalkyrie:BAAANQADCgUIBgAAAA==.Goodspeed:BAAANQAECgQIAgAAAA==.',
Gr='Grandpawolf:BAAANQAECgYIBgAAAA==.Graymoon:BAAANQADCgQICgAAAA==.Greywings:BAAANQAECgQIBwAAAA==.Grimroxs:BAAANQAECgUIDwAAAA==.Griptape:BAABNQAECn8bAAMSAAcK2BEsWgCKAQASAAcK2BEsWgCKAQAKAAEKAACG+QAeAAABNQAECgEIAQAIAAAAAA==.',
Gu='Guylapso:BAAANQADCgYIDgAAAA==.',
['Gå']='Gålahad:BAAANQAECgEIAQAAAA==.',
Ha='Hairydragon:BAAANQAECgQIBAABNQAECgkJLAAYAAIcAA==.Handerbug:BAABNQAECn8qAAMFAAkKjCX9AgDOAwAFAAkKjCX9AgDOAwAGAAEKAACXTwBkAAAAAA==.Handiebug:BAAANQADCgYIBgABNQAECgkJKgAFAIwlAA==.Handybug:BAAANQADCgYIDQABNQAECgkJKgAFAIwlAA==.',
He='Healtaxi:BAAANQAECgEIAQAAAA==.Heiler:BAABNQAECn8eAAIDAAgKlAWyjgBqAQADAAgKlAWyjgBqAQAAAA==.',
Hi='Hi:BAAANQAECgUICQAAAA==.',
Ho='Hogglethorp:BAAANQAECgIIAgAAAA==.Hokis:BAAANQADCgcICAAAAA==.Holyhooters:BAAANQADCggIFAAAAA==.Hornshatter:BAAANQAECgYIDgAAAA==.',
Hr='Hruroth:BAAANQADCgMIBAAAAA==.',
Ia='Iamevil:BAAANQADCggICAAAAA==.',
Ib='Ibis:BAAANQADCgUIBQAAAA==.',
Id='Idontrez:BAAANQAECgEIAQAAAA==.',
Il='Illadron:BAAANQAECggIDwAAAA==.',
In='Inala:BAAANQAECgYICAAAAA==.Infuzed:BAABNQAECn8qAAIMAAoKTxr6DgB1AQAMAAoKTxr6DgB1AQAAAA==.',
Io='Iove:BAABNQAECn8dAAIDAAkKsBeGGQCpAQADAAkKsBeGGQCpAQAAAA==.',
Ir='Ironface:BAAANQADCgQIBAAAAA==.',
It='Itsmykitty:BAAANQADCgEIAQABNQADCggIBwAIAAAAAA==.',
Ja='Jacksus:BAABNQAECn8WAAIKAAcKSR3GRAAGAgAKAAcKSR3GRAAGAgABNQAECgoKMgARAG0iAA==.',
Jd='Jdbud:BAAANQAECgQIBAAAAA==.Jdpot:BAAANQAECgQIDgAAAA==.',
Je='Jenaaidy:BAABNQAECn8aAAIBAAYKKhNfNACAAQABAAYKKhNfNACAAQAAAA==.Jesko:BAAANQADCgUICgAAAA==.',
Ji='Jimmies:BAAANQADCgEIAQAAAA==.',
Jo='Joedavola:BAAANQAECgUIBQAAAA==.Jooshie:BAAANQAECgMIBgABNQAECgoKFgAZAOshAA==.Jooshy:BAABNQAECn8kAAIaAAkKByIDBQBdAwAaAAkKByIDBQBdAwABNQAECgoKFgAZAOshAA==.Josher:BAAANQADCgEIAQABNQAECgoKFgAZAOshAA==.Joshieboba:BAABNQAECn8WAAIZAAoK6yF8BAAqAgAZAAoK6yF8BAAqAgAAAA==.Joyzee:BAAANQADCgcIEQAAAA==.',
Ju='Judge:BAABNQAECn8aAAICAAUKgwpkGQH1AAACAAUKgwpkGQH1AAAAAA==.Justviolence:BAAANQADCggIEAAAAA==.',
Jy='Jynrokka:BAABNQAECn8aAAISAAcKnyB3DwBnAQASAAcKnyB3DwBnAQAAAA==.',
Ka='Kanati:BAAANQADCgUIBgAAAA==.Katasaria:BAACNQAFFH8JAAIRAAMKihC1CgDfAAARAAMKihC1CgDfAAA1AAQKfy0AAhEACgr+HX4oABgDABEACgr+HX4oABgDAAAA.Katiebug:BAAANQADCggIHAAAAA==.Katiekat:BAAANQADCgQIBwAAAA==.Kaycee:BAAANQADCgEIAQABNQAECgEIAQAIAAAAAA==.Kayceedilla:BAAANQADCgQIBQABNQAECgEIAQAIAAAAAA==.Kaycer:BAAANQAECgEIAQAAAA==.',
Ke='Keeps:BAAANQADCgEIAwAAAA==.Kerl:BAAANQADCgYIBgAAAA==.Kestrell:BAABNQAECn8XAAQaAAcKgwjZNwDWAAAaAAUKggfZNwDWAAAbAAQKkgbtGQCgAAAcAAYKWA29DQCDAAAAAA==.Kevoni:BAAANQADCgMIAwAAAA==.',
Kh='Khorlock:BAAANQAECgQIDwAAAA==.Khorus:BAABNQAECn8bAAICAAcKixWCuACtAQACAAcKixWCuACtAQAAAA==.',
Ki='Kirana:BAAANQAECgQIDAAAAA==.',
Ko='Koalateectrl:BAAANQADCgUIBQAAAA==.',
Kr='Kravin:BAAANQAECgUIBQAAAA==.',
Ku='Kudrani:BAAANQADCgQICQABNQADCgYIBwAIAAAAAA==.',
Ky='Kynnas:BAABNQAECn8yAAINAAoKwA9hIQBBAgANAAoKwA9hIQBBAgAAAA==.',
La='Ladelin:BAAANQADCgEIAQAAAA==.Laneywine:BAAANQADCgEIAQAAAA==.Larinas:BAAANQAECgIIAgAAAA==.Larlifax:BAAANQAECgEIAQAAAA==.Lauxy:BAAANQAECgYICAAAAA==.',
Le='Leonuss:BAABNQAECn8yAAIRAAoKbSLLCACtAwARAAoKbSLLCACtAwAAAA==.Levìstus:BAAANQAECgcIEQAAAA==.Leylaní:BAABNQAECn8kAAIOAAgKMhOldQAkAgAOAAgKMhOldQAkAgAAAA==.',
Li='Lidria:BAAANQADCggIDQAAAA==.Lillinth:BAAANQAECgUJCQAAAA==.Lilmagedude:BAAANQAECgIIBAAAAA==.Lilmissblue:BAAANQADCgcICAAAAA==.Linoir:BAABNQAECn8oAAICAAoKAR+wKgAcAwACAAoKAR+wKgAcAwAAAA==.Livenasty:BAAANQAECgUIBwAAAA==.',
Lo='Loroessan:BAAANQAECggICAAAAA==.',
Lu='Lucylawladin:BAAANQAECgMIBAAAAA==.Lurry:BAAANQADCgQIBAAAAA==.',
Ly='Lykios:BAAANQADCgYIBgAAAA==.Lythea:BAAANQAECgUICAABNQAECgoKMwAcACEeAA==.Lytheum:BAABNQAECn8zAAIcAAoKIR51BABUAwAcAAoKIR51BABUAwAAAA==.',
Ma='Maatato:BAAANQADCgQIBAAAAA==.Magikon:BAAANQADCgEIAQAAAA==.Magista:BAAANQAECgUIBQAAAA==.Maitias:BAAANQADCggICwABNQAECgEIAQAIAAAAAA==.Malachar:BAABNQAECn8aAAIdAAcKWBARCwD+AAAdAAcKWBARCwD+AAAAAA==.Malboro:BAABNQAECn8aAAIWAAkKBwvTFADHAQAWAAkKBwvTFADHAQAAAA==.Maled:BAABNQAECn8UAAQeAAYKmgq4EgAeAQAeAAUKxAm4EgAeAQAWAAIKOwvIXgBoAAAVAAIKogRKMQFZAAAAAA==.Maloa:BAAANQADCgUIBQABNQAECgcIGgAFAKsYAA==.',
Me='Meldin:BAAANQAECgUIEQAAAA==.Melinoë:BAAANQADCgEIAgAAAA==.Method:BAABNQAECn8qAAMfAAkKuA57JgCrAQAfAAkKuA57JgCrAQACAAEKYAy5sgEuAAAAAA==.',
Mi='Miannya:BAABNQAECn8jAAIYAAkKrBstFgCeAgAYAAkKrBstFgCeAgAAAA==.Mignons:BAAANQAECgQIBAAAAA==.Mikuohashi:BAAANQAECgQIBAAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mineos:BAAANQAECgQICAAAAA==.Minipedro:BAAANQAECgUICAABNQAFFAMIBwAMAJ8RAA==.Mirmidon:BAAANQADCgEIAgAAAA==.Missingparts:BAAANQAECgQICgAAAA==.Mistamiso:BAAANQAECggICgABNQAECgoKKgAMAE8aAA==.Mistrmiso:BAAANQADCgEIAQABNQAECgoKKgAMAE8aAA==.',
Mm='Mmandalorian:BAAANQADCgQIBAAAAA==.',
Mo='Moahuntress:BAAANQADCgUICwAAAA==.Moonlyt:BAAANQADCggIGwAAAA==.Morgaine:BAAANQADCggIJAABNQAECgcICAAIAAAAAA==.Morn:BAABNQAECn8lAAIcAAoKLhfeEABIAgAcAAoKLhfeEABIAgAAAA==.',
Mu='Mundory:BAAANQADCgQIBAAAAA==.Mutalation:BAAANQAECgUIBgAAAA==.',
My='Myra:BAAANQADCgMIAwAAAA==.Mystu:BAAANQAECgQIBAAAAA==.',
Na='Nadià:BAAANQAECgYIDQAAAA==.Naila:BAAANQADCgEIAgAAAA==.',
Ne='Needagrip:BAABNQAECn8kAAISAAgKURbeQAD6AQASAAgKURbeQAD6AQAAAA==.Neonn:BAAANQABCgEIAQAAAA==.Netherid:BAAANQADCgQIBwAAAA==.Newman:BAAANQADCgEIAQAAAA==.',
Ni='Nidwick:BAAANQADCgIIAgAAAA==.Nifin:BAAANQAECgQICwAAAA==.',
No='Nojive:BAAANQADCgEIAQAAAA==.Notrobo:BAAANQAECgUIBQABNQAFFAMICQARAIoQAA==.',
Ny='Nystannia:BAAANQADCgEIAgABNQADCgYIBwAIAAAAAA==.Nystrip:BAAANQADCgEIAQAAAA==.',
On='Onyx:BAAANQADCgMIAwAAAA==.',
Oo='Oor:BAAANQAECgQIAwABNQAECgoKJQAHAHsdAA==.',
Or='Orannir:BAAANQADCgQIBAAAAA==.Orgrym:BAAANQAECgEIAQAAAA==.Orialis:BAAANQADCgUIBgAAAA==.Orlandbro:BAABNQAECn8hAAMTAAkKCxtDIABMAgATAAgKvhlDIABMAgAOAAMKoh4eEAHlAAAAAA==.',
Os='Oshiokiyo:BAAANQADCggIMgAAAA==.',
Pa='Patchs:BAAANQAECgYIBgAAAA==.Pawradox:BAABNQAECn8oAAIBAAkKVRTABAC0AQABAAkKVRTABAC0AQAAAA==.',
Pe='Peeves:BAAANQADCgMIAgABNQAECgkJKgAFAIwlAA==.',
Ph='Phenomenon:BAABNQAECn84AAIOAAoKBhsbBwBWAgAOAAoKBhsbBwBWAgAAAA==.',
Pi='Pitviper:BAAANQADCgIIAgAAAA==.',
Pl='Plina:BAABNQAECn8hAAICAAgKIBONowDZAQACAAgKIBONowDZAQAAAA==.',
Po='Ponglenis:BAAANQAECgMIBQABNQAECgUIBwAIAAAAAA==.Portalmaster:BAAANQADCgIJAgAAAA==.Poshiesty:BAABNQAECn8cAAIYAAoKPBJHBgCrAQAYAAoKPBJHBgCrAQAAAA==.Potatofox:BAAANQADCggICgAAAA==.Potatolor:BAABNQAECn8XAAIgAAkKtxCKIACHAQAgAAkKtxCKIACHAQAAAA==.',
Pr='Presto:BAAANQADCgMIAwAAAA==.',
Pu='Pulli:BAAANQADCgQIBAAAAA==.Pusinmyboot:BAAANQADCgEIAQAAAA==.',
Pv='Pve:BAABNQAECn8zAAMhAAoKOyFWAACcAgAhAAoKOyFWAACcAgAOAAEKMxFPTgFEAAAAAA==.',
Py='Pyx:BAAANQAECgQIBAAAAA==.',
Ra='Raehanji:BAAANQAECgEIAQAAAA==.Raiina:BAABNQAECn8pAAIHAAoK+BdXOQB5AgAHAAoK+BdXOQB5AgAAAA==.Rains:BAAANQAECgYIDwAAAA==.Rathane:BAABNQAECn82AAIOAAkKABh1UgB5AgAOAAkKABh1UgB5AgAAAA==.Razhj:BAAANQADCgIIAgAAAA==.',
Re='Reapr:BAABNQAECn8kAAIiAAgKHxlKMQAdAgAiAAgKHxlKMQAdAgAAAA==.Redrabbit:BAAANQAECgIIAgAAAA==.Reikpord:BAAANQADCggICAAAAA==.Rexx:BAAANQADCgYIDAAAAA==.',
Rh='Rhapsody:BAABNQAECn8aAAIjAAcKZiUAAwDfAgAjAAcKZiUAAwDfAgAAAA==.',
Ri='Rizzwan:BAAANQAECgQIBQAAAA==.',
Ro='Robotkirky:BAAANQAECgQIBAAAAA==.',
Ru='Runecleaver:BAABNQAECn8lAAIHAAoKex2PMACfAgAHAAoKex2PMACfAgAAAA==.Ruw:BAABNQAECn8YAAIkAAcKxhH5PwDNAQAkAAcKxhH5PwDNAQAAAA==.Ruwmage:BAAANQADCggICAAAAA==.',
Sa='Sardroth:BAABNQAECn8vAAMKAAkK4iRcCQB0AwAKAAkK4iRcCQB0AwAiAAIK5hOjlQBqAAAAAA==.Satavara:BAAANQAECgQICgAAAA==.',
Se='Seiba:BAAANQADCgEIAQAAAA==.',
Sh='Shapòópy:BAAANQAECgUICQAAAA==.Sharius:BAAANQADCggIBwAAAA==.Shavv:BAAANQADCgQICAAAAA==.Shawesome:BAAANQADCgYIBgAAAA==.Shiera:BAABNQAECn8WAAMXAAkKvw7CDwCsAQAXAAgKvw7CDwCsAQAQAAYKngW+SAEVAQAAAA==.',
Si='Sightlightx:BAAANQAECgQIDAAAAA==.Sigs:BAAANQADCgYIBgAAAA==.Silvershine:BAAANQADCggIDAAAAA==.Siryn:BAAANQAECgYICgAAAA==.',
Sl='Slaphaschel:BAAANQADCgMIAwAAAA==.',
Sm='Smallest:BAAANQADCgEIAQABNQAECgEIAQAIAAAAAA==.',
Sp='Sparkelynn:BAAANQADCgQIBgAAAA==.Spinlock:BAAANQADCgQIBAAAAA==.Spitfyre:BAAANQADCggICwAAAA==.',
Sq='Squeeze:BAAANQADCgMJAwAAAA==.',
St='Stonehammer:BAAANQADCgUIBQAAAA==.',
Su='Susa:BAAANQADCgMIBAAAAA==.',
Sy='Sylesta:BAABNQAECn8nAAMZAAkKChA9KADeAQAZAAkKChA9KADeAQAFAAYKdhEJYgBGAQAAAA==.Syrden:BAAANQADCggIDAABNQAECgkJKQAZAHEMAA==.',
Ta='Talís:BAAANQADCggIIgAAAA==.Taranis:BAAANQAECgcIDQAAAA==.',
Te='Teremen:BAAANQADCgUICwABNQAFFAcIDwABAFUYAA==.',
Th='Thandas:BAAANQADCgYIDQAAAA==.Theherooz:BAAANQAECgQIBAAAAA==.Thekarens:BAAANQAECgQICQAAAA==.Thiandra:BAAANQADCgEIAQAAAA==.Thniper:BAABNQAECn8mAAITAAoKbRnyGgB9AgATAAoKbRnyGgB9AgAAAA==.Thoriumaster:BAAANQADCgEIAQAAAA==.',
Ti='Tiamaria:BAABNQAECn8pAAIjAAkK2w4hWwAHAgAjAAkK2w4hWwAHAgAAAA==.Tihn:BAAANQADCgEIAgAAAA==.',
Tr='Trick:BAAANQADCgYIBgAAAA==.Trilbey:BAAANQADCgYICwAAAA==.Trismegistus:BAAANQADCgcICgAAAA==.',
Tw='Twittch:BAAANQADCgEIAQAAAA==.',
Ty='Tyinviril:BAACNQAFFH8PAAIBAAcKVRhtAgBqAgABAAcKVRhtAgBqAgA1AAQKf0AAAwEACgpxJBUBAOEDAAEACgpxJBUBAOEDAAMAAQpRAhacADQAAAAA.Tyrandice:BAAANQAECgIIBAABNQAECggIBAAIAAAAAA==.Tythoruin:BAAANQAECgMIAwABNQAFFAcIDwABAFUYAA==.Tyvireth:BAAANQADCggIEAABNQAFFAcIDwABAFUYAA==.',
Va='Varlund:BAAANQABCgEIAQAAAA==.',
Ve='Veraz:BAABNQAECn84AAMCAAkKcx87LgAPAwACAAkKcx87LgAPAwAjAAcKbAyAjwBvAQAAAA==.',
Vo='Vonawesome:BAAANQAECgcIDQAAAA==.Vorpalblade:BAABNQAECn8pAAIdAAkKaRK2EgD5AQAdAAkKaRK2EgD5AQAAAA==.',
Vy='Vylas:BAAANQADCgEIAQAAAA==.Vyraal:BAAANQAECgYICwAAAA==.',
Wa='Warloque:BAAANQADCgUIEwAAAA==.Warlorok:BAAANQADCgYIBwAAAA==.Warpsmithoor:BAAANQAECgYIBwABNQAECgoKJQAHAHsdAA==.',
We='Wend:BAABNQAECn8zAAIlAAoK1B3KAAAvAwAlAAoK1B3KAAAvAwAAAA==.Weywey:BAABNQAECn8aAAIOAAcKLgqVUQAOAQAOAAcKLgqVUQAOAQAAAA==.',
Wh='Whisperspeak:BAAANQADCgEIAQAAAA==.',
Wo='Wobblerslock:BAAANQADCgQICAABNQADCgcICQAIAAAAAA==.',
Wr='Wram:BAAANQAECgcICAAAAA==.Wreckamma:BAAANQAECgQIBQABNQAECgcIGwACAIsVAA==.Wreckturd:BAAANQAECgQIBAABNQAECgcIGwACAIsVAA==.Wreckuiem:BAAANQAECgQIBAABNQAECgcIGwACAIsVAA==.',
Wy='Wychlord:BAAANQAECgEIAQAAAA==.Wylder:BAAANQAECgQIDAAAAA==.',
Xe='Xenophilious:BAAANQAECgUIEQAAAA==.',
Xi='Xiomara:BAAANQADCgQICAAAAA==.Xiøn:BAAANQAECgIIAgAAAA==.',
Yn='Yn:BAAANQADCgIIAgAAAA==.',
Yu='Yumei:BAAANQADCgEIAQAAAA==.',
Ze='Zedal:BAAANQAECgEIAQAAAA==.Zelios:BAAANQADCgYIBgAAAA==.',
Zo='Zoemarie:BAAANQADCgUIBgAAAA==.Zoinx:BAABNQAECn8kAAIVAAgKRR4ZQgCMAgAVAAgKRR4ZQgCMAgAAAA==.',
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
