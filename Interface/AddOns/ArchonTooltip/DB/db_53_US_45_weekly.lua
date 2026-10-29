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

local lookup = {'Priest-Shadow','Paladin-Retribution','Priest-Holy','Druid-Feral','Druid-Balance','Druid-Guardian','Unknown-Unknown','Mage-Arcane','Shaman-Restoration','Priest-Discipline','DeathKnight-Unholy','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Shaman-Elemental','Warrior-Arms','DeathKnight-Blood','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Monk-Windwalker','Rogue-Subtlety','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Frost','Warrior-Protection','Warlock-Affliction','Paladin-Protection','Monk-Mistweaver','Hunter-Survival','Paladin-Holy','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adaila:BAABNQAECn8gAAIBAAkKJQlULwCpAQABAAkKJQlULwCpAQAAAA==.Ade:BAAANQAECgMIBAAAAA==.',
Ai='Aiir:BAABNQAECn8bAAICAAcKaguzqAAFAQACAAcKaguzqAAFAQAAAA==.',
Aj='Ajaki:BAAANQAECgUIBQAAAA==.Ajaxstar:BAAANQAECgUIBwAAAA==.',
Al='Alethe:BAABNQAECn8qAAIDAAoK6RbBHgBqAgADAAoK6RbBHgBqAgAAAA==.Alfivin:BAAANQAECgUICQAAAA==.All:BAABNQAECn8bAAQEAAcKyxe/FACwAQAFAAcKQxTrSgC6AQAEAAcKahO/FACwAQAGAAIKex+pRAChAAAAAA==.Almondor:BAAANQADCgYIBgAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgAAAA==.Ambridgerose:BAAANQADCggIDwAAAA==.Ammariel:BAAANQAECgQIBQAAAA==.Amyis:BAAANQAECgYICAABNQAFFAEIAgAHAAAAAA==.',
An='Antiwend:BAABNQAECn8XAAIIAAkK+wuTWgCdAQAIAAkK+wuTWgCdAQAAAA==.',
Ap='Aphaea:BAAANQAECgYIBgAAAA==.Apocalypsus:BAAANQAECgMIAwAAAA==.Appolyin:BAAANQAECgUIBgAAAA==.',
Ar='Arlan:BAAANQADCgIIAgAAAA==.',
As='Ashtomb:BAAANQADCgYIBgABNQAECgoKLQAJAOsdAA==.',
At='Ata:BAAANQAECgIIAQAAAA==.Athenâ:BAAANQAECgYICwAAAA==.',
Au='Audrac:BAAANQADCgEIAQAAAA==.',
Av='Availis:BAAANQADCggIDgAAAA==.Avari:BAAANQADCgMIAwABNQADCgYIBgAHAAAAAA==.',
Aw='Awawa:BAAANQADCgQIBAAAAA==.',
Az='Azariel:BAABNQAECn8tAAQDAAoKaQ3oMQD2AQADAAkK3g7oMQD2AQAKAAEKSAHXMgAbAAABAAEKAACslQAPAAAAAA==.Azorahai:BAABNQAECn8ZAAILAAYKuAnrhQAJAQALAAYKuAnrhQAJAQAAAA==.Azshalia:BAAANQAECgUIDwAAAA==.',
Ba='Bacardiand:BAABNQAECn8dAAIMAAkKuBYYEQBYAgAMAAkKuBYYEQBYAgAAAA==.Baishu:BAABNQAECn8mAAMNAAoKjx03HQCwAgANAAkKjx03HQCwAgAOAAEKAACOdgAhAAAAAA==.Balfazar:BAAANQAECgYIDAAAAA==.Banilibug:BAAANQAECgEIAQAAAA==.Baraddur:BAAANQADCgQIBgAAAA==.Baradun:BAAANQAECgUIBwAAAA==.Barrymanalow:BAABNQAECn8pAAIBAAkKcQezIgDxAAABAAkKcQezIgDxAAAAAA==.',
Be='Beachmouse:BAAANQADCgYIBgABNQAECgEJAQAHAAAAAA==.Bearclaw:BAAANQADCgUIBQAAAA==.Beorngoat:BAAANQAECgUICgAAAA==.Bernarn:BAAANQADCgQIBAAAAA==.',
Bl='Blackout:BAAANQAECgYIDAABNQAECgoKMQANAPwaAA==.Bloodpool:BAAANQAECgEIAQAAAA==.Bluerabbit:BAAANQAECgEIAgABNQAECgoKMgAFAAclAA==.',
Bo='Bobbybrady:BAAANQADCgUICgAAAA==.Bokni:BAAANQAECgEIAQAAAA==.',
Bu='Bufforc:BAAANQADCgYIBgAAAA==.Buildie:BAAANQADCgcIBwAAAA==.Bushwhacker:BAAANQAECgYIBwAAAA==.Butterbean:BAABNQAECn8nAAIPAAoK4RmGMAAeAgAPAAoK4RmGMAAeAgAAAA==.',
Ca='Calice:BAAANQADCgMIAwAAAA==.Cappally:BAAANQADCgUIBgAAAA==.Carch:BAEANQADCgUIBQAAAA==.Cashinout:BAAANQAECggIAgAAAA==.',
Ch='Charizard:BAAANQAECggIAgAAAA==.Chickenhawk:BAAANQAECgQIDAAAAA==.Chicxulub:BAAANQADCgcIDAAAAA==.Chonkyninja:BAAANQAECgQJBAAAAA==.Choroksaek:BAAANQADCggIJAAAAA==.',
Ci='Citan:BAAANQAECgcIDAAAAA==.',
Cl='Classfantasy:BAABNQAECn8uAAMQAAoK1RlPHAAZAgAQAAkK2hpPHAAZAgAJAAYKrQZ40ADGAAAAAA==.',
Co='Condesate:BAAANQAECgcIBwAAAA==.',
Cr='Crazytoe:BAAANQAECgEIAQAAAA==.Croghon:BAAANQAECgIIAgAAAA==.',
Ct='Cthruthyveil:BAAANQAECgQIDwAAAA==.',
Cu='Cursè:BAAANQABCgIIAgABNQAECggIBwAHAAAAAA==.',
Cy='Cythrandir:BAAANQAECgIIAwABNQAECgoKKwAIADcbAA==.',
Da='Dany:BAAANQAECgQIBQAAAA==.Darkriff:BAAANQABCggIEQAAAA==.Daruta:BAAANQADCgQIBgAAAA==.Daytona:BAAANQAECgcIDwAAAA==.',
Dd='Ddccssff:BAAANQAECgUICwAAAA==.',
De='Deathcoiled:BAAANQAECgIIAgAAAA==.Dethrahzen:BAAANQAECgEIAgAAAA==.',
Di='Dindunuthin:BAAANQAECgMIBAAAAA==.Dipika:BAAANQAECgQIBAAAAA==.Disektor:BAABNQAECn8eAAIRAAkKWhQrjAD+AQARAAkKWhQrjAD+AQAAAA==.',
Dk='Dkray:BAABNQAECn8bAAMLAAYKTwe3nADEAAALAAUKVAW3nADEAAASAAUKsgZakADDAAAAAA==.',
Do='Donnettlen:BAAANQADCgcICAAAAA==.Donorli:BAAANQADCgYIBgAAAA==.Dotsfordayz:BAAANQAECgEIAwABNQAECgEIAQAHAAAAAA==.Douglit:BAAANQAECgQIBAAAAA==.',
Dr='Dronesworn:BAAANQADCgUICgAAAA==.Drstránge:BAAANQAECgQIBgAAAA==.',
Du='Dugatotems:BAABNQAECn8oAAMJAAoKnRWybADFAQAJAAoKnRWybADFAQAQAAgKbQqueQC1AQAAAA==.Dunkle:BAABNQAECn8xAAIRAAoKThsBKgA4AgARAAoKThsBKgA4AgAAAA==.Duskhawk:BAABNQAECn8eAAMPAAcK9AUfoQDsAAAPAAcK9AUfoQDsAAATAAIKWwE/gQBBAAAAAA==.',
Dy='Dynxy:BAAANQADCgYIBgAAAA==.',
Eb='Ebonise:BAAANQAECgQIBAABNQAECgQIDwAHAAAAAA==.',
Ed='Edrelang:BAAANQADCgMIAgAAAA==.',
El='Elivien:BAAANQADCgIIAgABNQADCgYIBgAHAAAAAA==.Ellechero:BAAANQAECgIIAQAAAA==.',
Eo='Eogimboonn:BAAANQADCgYIBgAAAA==.',
Er='Eredin:BAAANQADCgMIAwAAAA==.Erinna:BAAANQAECgIIAgAAAA==.Erommêl:BAAANQAECgQIBAAAAA==.',
Fa='Fafner:BAAANQADCgEIAQAAAA==.Farsha:BAAANQADCgYIBgAAAA==.',
Fe='Fextrius:BAABNQAECn8jAAIRAAkKMxjpOADvAQARAAkKMxjpOADvAQAAAA==.',
Fr='Frthckr:BAAANQADCgIIAgAAAA==.',
Fu='Funnelcakes:BAAANQADCgEIAQAAAA==.',
Ga='Garreux:BAAANQADCgIIAQAAAA==.Gazebo:BAAANQADCgUICwAAAA==.',
Ge='Genghis:BAAANQAECggIAgAAAA==.',
Gh='Ghast:BAABNQAECn9FAAMUAAoKiw6mXQBLAQAUAAoKFQ6mXQBLAQAVAAIKqRPlYABjAAAAAA==.',
Gi='Giddley:BAAANQABCgMIAwAAAA==.Gigaflare:BAABNQAECn8yAAMWAAoKfxBtBgDYAQAWAAoKfxBtBgDYAQAIAAgKHwXZDAF3AQAAAA==.',
Gl='Gladîator:BAAANQADCgEJAQAAAA==.Glahmgold:BAAANQAECgUICAAAAA==.',
Go='Goatale:BAABNQAECn80AAIXAAkKshzzFACtAgAXAAkKshzzFACtAgAAAA==.Goathunt:BAAANQADCggICAABNQAECgkJNAAXALIcAA==.Goatseer:BAABNQAECn8ZAAIMAAgKQhg8EgBGAgAMAAgKQhg8EgBGAgAAAA==.Goatwizard:BAAANQAECgMIBAAAAA==.Gobblynn:BAAANQADCggIFgAAAA==.Goldvalkyrie:BAAANQADCggIDQAAAA==.Goodspeed:BAAANQAECgUIAwAAAA==.',
Gr='Grandpawolf:BAAANQAECgYICAAAAA==.Graymoon:BAAANQADCgQICAAAAA==.Greywings:BAAANQAECgQIBwAAAA==.Grimnaw:BAAANQADCgcIBwAAAA==.Grimroxs:BAABNQAECn8ZAAIYAAgKPwfXVQAEAQAYAAgKPwfXVQAEAQAAAA==.Griptape:BAABNQAECn8bAAMSAAcK2BEsWgCKAQASAAcK2BEsWgCKAQALAAEKAACG+QAeAAABNQAECgEIAQAHAAAAAA==.',
Gu='Guylapso:BAAANQADCgYIDQAAAA==.',
['Gå']='Gålahad:BAAANQAECgEIAQAAAA==.',
Ha='Hairydragon:BAAANQAECgQIBAABNQAECgkJNAAXALIcAA==.Handerbug:BAABNQAECn8yAAMFAAoKByX9AgDOAwAFAAoKByX9AgDOAwAGAAEKAACXTwBkAAAAAA==.Handiebug:BAAANQADCgYIBgABNQAECgoKMgAFAAclAA==.Handybug:BAAANQAECgEIAQABNQAECgoKMgAFAAclAA==.',
He='Healtaxi:BAAANQAECgEIAQAAAA==.Heiler:BAABNQAECn8kAAIDAAgKoAupZgAjAQADAAgKoAupZgAjAQAAAA==.',
Hi='Hi:BAAANQAECgUICQAAAA==.',
Ho='Hogglethorp:BAAANQAECgIIAgAAAA==.Hokis:BAAANQADCgcIBwAAAA==.Holyhooters:BAAANQADCggIEwAAAA==.Horns:BAAANQADCgYIHAAAAA==.Hornshatter:BAAANQAECgYIEwAAAA==.',
Hr='Hruroth:BAAANQADCgMIBAAAAA==.',
Ia='Iamevil:BAAANQAECgMIAwAAAA==.',
Ib='Ibis:BAAANQADCgUIBQAAAA==.',
Id='Idontrez:BAAANQAECgEIAQAAAA==.',
Ig='Igh:BAAANQAECgIIAgAAAA==.',
Il='Illadron:BAAANQAECggIEAAAAA==.',
In='Inala:BAAANQAECgUIDAAAAA==.Infuzed:BAABNQAECn8xAAINAAoK/BpqGwC+AgANAAoK/BpqGwC+AgAAAA==.',
Io='Iove:BAABNQAECn8fAAIDAAoK/RkJNADsAQADAAoK/RkJNADsAQAAAA==.',
Ir='Ironface:BAAANQADCgQIBAAAAA==.',
It='Itsmykitty:BAAANQABCgIIAgABNQAECggIBwAHAAAAAA==.',
Ja='Jacksus:BAABNQAECn8fAAILAAoKfhxSCQCOAgALAAoKfhxSCQCOAgABNQAECgoKOQARAEImAA==.',
Jd='Jdbud:BAAANQAECgQIBAAAAA==.Jdpot:BAAANQAECgUIEQAAAA==.',
Je='Jenaaidy:BAABNQAECn8hAAIBAAcK+hFfNACAAQABAAcK+hFfNACAAQAAAA==.Jesko:BAAANQADCgUICAAAAA==.',
Ji='Jimmies:BAAANQABCgMIBQAAAA==.',
Jo='Joedavola:BAAANQAECgQIBgAAAA==.Jooshie:BAAANQAECgMIBgABNQAECgoKFwAZAOshAA==.Jooshy:BAABNQAECn8kAAIaAAkKByIDBQBdAwAaAAkKByIDBQBdAwABNQAECgoKFwAZAOshAA==.Josher:BAAANQADCgEIAQABNQAECgoKFwAZAOshAA==.Joshieboba:BAABNQAECn8XAAIZAAoK6yGHCQAtAwAZAAoK6yGHCQAtAwAAAA==.Joyzee:BAAANQADCgcIEQAAAA==.',
Ju='Judge:BAABNQAECn8eAAICAAUKIgxkGQH1AAACAAUKIgxkGQH1AAAAAA==.Justviolence:BAAANQADCggIEAAAAA==.',
Jy='Jynrokka:BAABNQAECn8hAAISAAgKYB80KAB/AgASAAgKYB80KAB/AgAAAA==.',
Ka='Kanati:BAAANQADCgUIBQAAAA==.Katasaria:BAACNQAFFH8NAAIRAAQKihDcEQDTAAARAAQKihDcEQDTAAA1AAQKfzAAAhEACgqNIn4oABgDABEACgqNIn4oABgDAAAA.Katiebug:BAAANQADCggIGwAAAA==.Katiekat:BAAANQADCgQIBgAAAA==.Kaycee:BAAANQADCgEIAQABNQAECgEIAQAHAAAAAA==.Kayceedilla:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Kaycer:BAAANQAECgEIAQAAAA==.',
Ke='Keeps:BAAANQADCgEIAQAAAA==.Kerl:BAAANQADCgYIBgAAAA==.Kestrell:BAABNQAECn8aAAQaAAkKZwvZNwDWAAAaAAYK6wbZNwDWAAAbAAcKkQ1bEQC9AAAcAAQKkgbtGQCgAAAAAA==.Kevoni:BAAANQADCgMIAwAAAA==.',
Kh='Khorlock:BAAANQAECgQIDwAAAA==.Khorus:BAABNQAECn8bAAICAAcKixWCuACtAQACAAcKixWCuACtAQAAAA==.',
Ki='Kirana:BAAANQAECgUIDQAAAA==.',
Ko='Koalateectrl:BAAANQADCgUIBQAAAA==.',
Kr='Kravin:BAAANQAECgQICAAAAA==.',
Ku='Kudrani:BAAANQADCgQIBwABNQADCgYIBgAHAAAAAA==.',
Ky='Kynnas:BAABNQAECn8yAAIOAAoKwA9hIQBBAgAOAAoKwA9hIQBBAgAAAA==.',
La='Laneywine:BAAANQABCgEIAQAAAA==.Larinas:BAAANQAECgIIAwAAAA==.Larlifax:BAAANQAECgIIAQAAAA==.Lauxy:BAAANQAECgcICgAAAA==.',
Le='Leonuss:BAABNQAECn85AAIRAAoKQibLCACtAwARAAoKQibLCACtAwAAAA==.Levìstus:BAABNQAECn8aAAIdAAgKHBOKLAB6AQAdAAgKHBOKLAB6AQAAAA==.Leylaní:BAABNQAECn8qAAIPAAgK4xOldQAkAgAPAAgK4xOldQAkAgAAAA==.',
Li='Lidria:BAAANQADCggIDQAAAA==.Lillinth:BAAANQAECgUJCQAAAA==.Lilmagedude:BAAANQAECgIIBAAAAA==.Lilmissblue:BAAANQADCgcIBwAAAA==.Linoir:BAABNQAECn8xAAICAAoKCSAPHgCYAgACAAoKCSAPHgCYAgAAAA==.Livenasty:BAAANQAECgUIBwABNQAECggIAgAHAAAAAA==.',
Lo='Loroessan:BAAANQAECggICgAAAA==.',
Lu='Lucylawladin:BAAANQAECgMIBAAAAA==.Lurry:BAAANQADCgQIBAAAAA==.',
Ly='Lykios:BAAANQADCgYIBgAAAA==.Lythea:BAAANQAECgYICQABNQAECgoKPAAbALYeAA==.Lytheum:BAABNQAECn88AAIbAAoKth51BABUAwAbAAoKth51BABUAwAAAA==.',
Ma='Maatato:BAAANQADCgQIBAAAAA==.Magikon:BAAANQADCgEIAQAAAA==.Magista:BAAANQAECgUIBQAAAA==.Maitias:BAAANQAECgQIBAABNQADCggIDgAHAAAAAA==.Malachar:BAABNQAECn8hAAIeAAgKyw6HEgAVAQAeAAgKyw6HEgAVAQAAAA==.Malboro:BAABNQAECn8cAAIVAAkK6AvTFADHAQAVAAkK6AvTFADHAQAAAA==.Maled:BAABNQAECn8aAAQfAAcKPwq4EgAeAQAfAAUKxAm4EgAeAQAVAAMKbgrWEgCDAAAUAAIKogRKMQFZAAAAAA==.Maloa:BAAANQADCgUIBQABNQAECggIIQAFAPUWAA==.',
Me='Meldin:BAABNQAECn8ZAAIPAAgKhRsZVACgAQAPAAgKhRsZVACgAQAAAA==.Method:BAABNQAECn80AAMgAAoKshGcDgC0AQAgAAoKshGcDgC0AQACAAIKYAy5sgEuAAAAAA==.',
Mi='Miannya:BAABNQAECn8jAAIXAAkKrBstFgCeAgAXAAkKrBstFgCeAgAAAA==.Mignons:BAAANQAECgQIBAAAAA==.Mikuohashi:BAAANQAECgQIBAAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mineos:BAAANQAECgUIDAAAAA==.Minipedro:BAAANQAECgUICAABNQAFFAMIBwANAJ8RAA==.Miracleman:BAAANQAECgEIAQAAAA==.Mirmidon:BAAANQABCggIEgAAAA==.Missingparts:BAAANQAECgQICQAAAA==.Mistamiso:BAAANQAECgcIDAABNQAECgoKMQANAPwaAA==.Mistrmiso:BAAANQADCgEIAQABNQAECgoKMQANAPwaAA==.',
Mm='Mmandalorian:BAAANQADCgQIBAAAAA==.',
Mo='Moahuntress:BAAANQADCgUICQAAAA==.Moonlyt:BAAANQADCggIGQAAAA==.Morgaine:BAAANQADCggIJAABNQAECgUIBgAHAAAAAA==.Morn:BAABNQAECn8pAAIbAAoKLhfeEABIAgAbAAoKLhfeEABIAgAAAA==.',
Mu='Mundory:BAAANQADCgQIBAAAAA==.Mutalation:BAAANQAECgcICgAAAA==.',
My='Myra:BAAANQADCgMIAwAAAA==.Mystu:BAAANQAECgMIBAAAAA==.',
Na='Nadià:BAAANQAECgUIEQAAAA==.',
Ne='Needagrip:BAABNQAECn8qAAISAAgKURZCJwBfAQASAAgKURZCJwBfAQAAAA==.Neonn:BAAANQABCgEIAQAAAA==.Netherid:BAAANQADCgQIBgAAAA==.',
Ni='Nidwick:BAAANQADCgIIAgAAAA==.Nifin:BAAANQAECgQICwAAAA==.',
No='Notrobo:BAAANQAECgYIBgABNQAFFAQIDQARAIoQAA==.',
Ny='Nystannia:BAAANQADCgEIAQABNQADCgYIBgAHAAAAAA==.',
On='Onyx:BAAANQADCgMIAwAAAA==.',
Oo='Oor:BAAANQAECgQIAwABNQAECgoKLQAJAOsdAA==.Oormoonmoon:BAAANQADCggICAAAAA==.',
Or='Orannir:BAAANQADCgQIBAAAAA==.Orgrym:BAAANQAECgQIBQAAAA==.Orialis:BAAANQADCgUIBQAAAA==.Orlandbro:BAABNQAECn8qAAMTAAoK9RgNDQAAAgATAAoKORYNDQAAAgAPAAMKoh4eEAHlAAAAAA==.',
Os='Oshiokiyo:BAAANQADCggIMwAAAA==.',
Pa='Patchs:BAAANQAECgUIBwAAAA==.Pawradox:BAABNQAECn8wAAIBAAkKVRQ2EwCXAQABAAkKVRQ2EwCXAQAAAA==.',
Pe='Peeves:BAAANQADCgMIAgABNQAECgoKMgAFAAclAA==.',
Ph='Phenomenon:BAABNQAECn9AAAIPAAoKFx24IAAVAwAPAAoKFx24IAAVAwAAAA==.',
Pi='Pitviper:BAAANQADCgIIAgAAAA==.',
Pl='Plina:BAABNQAECn8nAAICAAgK0xQhbwB2AQACAAgK0xQhbwB2AQAAAA==.',
Po='Ponglenis:BAAANQAECgMIBwABNQAECggIAgAHAAAAAA==.Portalmaster:BAAANQADCgIJAgAAAA==.Poshiesty:BAABNQAECn8gAAIXAAoK8RSzEwCsAQAXAAoK8RSzEwCsAQAAAA==.Potatofox:BAAANQADCggICgAAAA==.Potatolor:BAABNQAECn8bAAIhAAkKVBKKIACHAQAhAAkKVBKKIACHAQAAAA==.',
Pr='Presto:BAAANQADCgMIAwAAAA==.',
Pu='Pulli:BAAANQADCgQIBAAAAA==.Pusinmyboot:BAAANQADCgEIAQAAAA==.',
Pv='Pve:BAABNQAECn89AAMiAAoKZyLSAACSAwAiAAoKZyLSAACSAwAPAAEKMxFPTgFEAAAAAA==.',
Py='Pyx:BAAANQAECgQIBAAAAA==.',
Ra='Raehanji:BAAANQADCgQICgAAAA==.Raiina:BAABNQAECn8tAAIJAAoK9RpXOQB5AgAJAAoK9RpXOQB5AgAAAA==.Rains:BAABNQAECn8WAAIIAAYKThUJ7wCsAQAIAAYKThUJ7wCsAQAAAA==.Raora:BAAANQAECgMIAwAAAA==.Rathane:BAABNQAECn86AAIPAAoKMRZ1UgB5AgAPAAoKMRZ1UgB5AgAAAA==.Razhj:BAAANQADCgIIAgAAAA==.',
Re='Reapr:BAABNQAECn8qAAIdAAgKHxlKMQAdAgAdAAgKHxlKMQAdAgAAAA==.Redrabbit:BAAANQAECgIIAgAAAA==.Reikpord:BAAANQADCggICAAAAA==.Rexx:BAAANQADCgYICgAAAA==.',
Rh='Rhapsody:BAABNQAECn8hAAIjAAgKxyXkBgBdAwAjAAgKxyXkBgBdAwAAAA==.',
Ri='Rizzwan:BAAANQAECgQIBQAAAA==.',
Ro='Robotkirky:BAAANQAECgQIBAAAAA==.',
Ru='Runecleaver:BAABNQAECn8tAAIJAAoK6x2PMACfAgAJAAoK6x2PMACfAgAAAA==.Ruw:BAABNQAECn8bAAIkAAgKDxH5PwDNAQAkAAgKDxH5PwDNAQAAAA==.Ruwmage:BAAANQADCggICAAAAA==.',
Sa='Sardroth:BAABNQAECn84AAMLAAoKqCNcCQB0AwALAAoKqCNcCQB0AwAdAAIK5hOjlQBqAAAAAA==.Satavara:BAAANQAECgQICgAAAA==.',
Se='Seiba:BAAANQABCgMIAwAAAA==.',
Sh='Shapòópy:BAAANQAECgUIDQAAAA==.Sharius:BAAANQAECggIBwAAAA==.Shavv:BAAANQADCgQIBgAAAA==.Shawesome:BAAANQADCggICAAAAA==.Shiera:BAABNQAECn8WAAMWAAkKvw7CDwCsAQAWAAgKvw7CDwCsAQAIAAYKngW+SAEVAQAAAA==.',
Si='Sightlightx:BAAANQAECgUIEQAAAA==.Sigs:BAAANQADCgYIBgAAAA==.Silvershine:BAAANQADCggICwAAAA==.Siryn:BAAANQAECgYICgAAAA==.',
Sl='Slaphaschel:BAAANQADCgMIAwAAAA==.',
Sm='Smallest:BAAANQADCgEIAQABNQAECgEIAQAHAAAAAA==.',
Sn='Sneakygoat:BAAANQAECgIIAgABNQAECgkJNAAXALIcAA==.',
Sp='Sparkelynn:BAAANQADCgQIBgAAAA==.Spinlock:BAAANQADCgQIBAAAAA==.Spitfyre:BAAANQADCggICwAAAA==.',
Sq='Squeeze:BAAANQADCgMJAwAAAA==.',
St='Stonehammer:BAAANQADCgUIBgAAAA==.',
Su='Susa:BAAANQADCgMIBAAAAA==.',
Sy='Sylesta:BAABNQAECn8wAAMZAAoKyhXgCwB4AgAZAAoKyhXgCwB4AgAFAAYKdhEJYgBGAQAAAA==.Syrden:BAAANQADCggIDAABNQAECgoKMgAZADAOAA==.',
Ta='Talís:BAAANQADCggIIQAAAA==.Tancia:BAAANQAECgEIAQAAAA==.Taranis:BAABNQAECn8VAAMQAAgK4AsTlgBtAQAQAAcKVAoTlgBtAQAJAAcKyAaRYQAZAQAAAA==.Taverrek:BAAANQADCgIIAgAAAA==.',
Te='Teremen:BAAANQADCgUICQABNQAFFAgIEQABAP4VAA==.',
Th='Thandas:BAAANQADCgYIDQAAAA==.Theherooz:BAAANQAECgQIBAAAAA==.Thekarens:BAAANQAECgQICAAAAA==.Thniper:BAABNQAECn8mAAITAAoKbRnyGgB9AgATAAoKbRnyGgB9AgAAAA==.Thoriumaster:BAAANQADCgcIBwAAAA==.',
Ti='Tiamaria:BAABNQAECn8pAAIjAAkK2w4hWwAHAgAjAAkK2w4hWwAHAgAAAA==.',
Tr='Trick:BAAANQADCgYIBgAAAA==.Trilbey:BAAANQADCgYICwAAAA==.Trismegistus:BAAANQADCgcICgAAAA==.',
Tw='Twittch:BAAANQABCgEIAQAAAA==.',
Ty='Tyinithyr:BAAANQAECgUIBQABNQAFFAgIEQABAP4VAA==.Tyinviril:BAACNQAFFH8RAAIBAAgK/hVtAgBqAgABAAgK/hVtAgBqAgA1AAQKf0cAAwEACgpRJhUBAOEDAAEACgpRJhUBAOEDAAMABwpJFsEyAPIBAAAA.Tyrandice:BAAANQAECgIIAwABNQAECggIAwAHAAAAAA==.Tythoruin:BAAANQAECgMIAwABNQAFFAgIEQABAP4VAA==.Tyvireth:BAAANQADCggIDgABNQAFFAgIEQABAP4VAA==.',
Va='Varlund:BAAANQABCgEIAQAAAA==.',
Ve='Veraz:BAABNQAECn8+AAMCAAoKSR87LgAPAwACAAoKSR87LgAPAwAjAAcKbAyAjwBvAQAAAA==.',
Vo='Vonawesome:BAAANQAECgcIDAAAAA==.Vorpalblade:BAABNQAECn8yAAIeAAoK2xKoCADHAQAeAAoK2xKoCADHAQAAAA==.',
Vy='Vylas:BAAANQADCgEIAQAAAA==.Vyraal:BAAANQAECgUIDwAAAA==.',
Wa='Warloque:BAAANQADCgUIEAAAAA==.Warlorok:BAAANQADCgYIBgAAAA==.Warpsmithoor:BAAANQAECgYIBwABNQAECgoKLQAJAOsdAA==.',
We='Wend:BAABNQAECn89AAMlAAoKfR7KAAAvAwAlAAoKfR7KAAAvAwAIAAEK8QtUIQE/AAAAAA==.Weywey:BAABNQAECn8gAAIPAAcK+ArGrwClAQAPAAcK+ArGrwClAQAAAA==.',
Wh='Whisperspeak:BAAANQABCgEIAQAAAA==.',
Wo='Wobblerslock:BAAANQADCgQICAABNQADCgcICQAHAAAAAA==.',
Wr='Wram:BAAANQAECgUIBgAAAA==.Wreckamma:BAAANQAECgUICAABNQAECgcIGwACAIsVAA==.Wreckturd:BAAANQAECgUIBwABNQAECgcIGwACAIsVAA==.Wreckuiem:BAAANQAECgQIBAABNQAECgcIGwACAIsVAA==.',
Wy='Wychlord:BAAANQAECgEIAQAAAA==.Wylder:BAAANQAECgUIEQAAAA==.',
Xe='Xenophilious:BAABNQAECn8UAAICAAYKTggKBAEYAQACAAYKTggKBAEYAQAAAA==.',
Xi='Xiomara:BAAANQADCgQIBgAAAA==.Xiøn:BAAANQAECgIIAgAAAA==.',
Xz='Xzahchky:BAAANQABCgQIBAAAAA==.',
Yn='Yn:BAAANQADCgIIAgAAAA==.',
Ze='Zelios:BAAANQADCgYIBgAAAA==.',
Zo='Zoemarie:BAAANQADCgUICQAAAA==.Zoinx:BAABNQAECn8pAAIUAAgKRR4ZQgCMAgAUAAgKRR4ZQgCMAgAAAA==.',
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
