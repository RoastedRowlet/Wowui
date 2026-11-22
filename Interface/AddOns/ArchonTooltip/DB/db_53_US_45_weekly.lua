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

local lookup = {'Priest-Shadow','Paladin-Retribution','Priest-Holy','Druid-Feral','Druid-Balance','Druid-Guardian','DeathKnight-Blood','Mage-Arcane','Shaman-Restoration','Unknown-Unknown','Priest-Discipline','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Protection','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Shaman-Elemental','Warrior-Arms','Hunter-Marksmanship','Warlock-Destruction','Mage-Frost','Monk-Windwalker','Rogue-Subtlety','Paladin-Protection','DemonHunter-Vengeance','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Hunter-Survival','Paladin-Holy','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Bronzebeard',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Adaila:BAABNQAECn8gAAIBAAkKJQlULwCpAQABAAkKJQlULwCpAQAAAA==.Ade:BAAANQAECgIIBgAAAA==.',
Ai='Aiir:BAABNQAECn8uAAICAAkKWgzWsABuAQACAAkKWgzWsABuAQAAAA==.',
Aj='Ajaki:BAAANQAECgUIBQAAAA==.Ajaxstar:BAAANQAECgUIBwAAAA==.',
Al='Alethe:BAABNQAECn8vAAIDAAoKkRdsOQCDAgADAAoKkRdsOQCDAgAAAA==.Alfivin:BAAANQAECgUICQAAAA==.All:BAABNQAECn8bAAQEAAcKyxe/FACwAQAFAAcKQxTrSgC6AQAEAAcKahO/FACwAQAGAAIKex+pRAChAAAAAA==.Almondor:BAAANQADCgYIBgAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgAAAA==.Ambridgerose:BAAANQADCggIDwAAAA==.Ammariel:BAAANQAECgQIBQAAAA==.Amyis:BAAANQAECgYICAABNQAECgoKGAAHAFwQAA==.',
An='Antiwend:BAABNQAECn8cAAIIAAoK0A8zYwDwAQAIAAoK0A8zYwDwAQAAAA==.',
Ap='Aphaea:BAAANQAECgcICgAAAA==.Apocalypsus:BAAANQAECgUICQAAAA==.Appolyin:BAAANQAECgYIBgAAAA==.',
Ar='Arlan:BAAANQADCgIIAgAAAA==.',
As='Ashtomb:BAAANQAECgIIAgABNQAECgoKQAAJACIeAA==.',
At='Ata:BAAANQAECgIIAgAAAA==.Athenâ:BAAANQAECgYIDAAAAA==.',
Au='Audrac:BAAANQADCgEIAQAAAA==.',
Av='Availis:BAAANQADCggIDgAAAA==.Avari:BAAANQADCgMIAwABNQADCgYIBgAKAAAAAA==.',
Aw='Awawa:BAAANQADCgQIBAAAAA==.',
Az='Azariel:BAABNQAECn8tAAQDAAoKaQ1qWwDRAQADAAkK3g5qWwDRAQALAAEKSAHXMgAbAAABAAEKAACslQAPAAAAAA==.Azorahai:BAABNQAECn8hAAMMAAgKRAjrhQAJAQAMAAYKuAnrhQAJAQANAAYKTQW+eADEAAAAAA==.Azshalia:BAABNQAECn8XAAIOAAcKQQ1BIQBDAQAOAAcKQQ1BIQBDAQAAAA==.',
Ba='Bacardiand:BAABNQAECn8dAAIPAAkKuBYYEQBYAgAPAAkKuBYYEQBYAgAAAA==.Baishu:BAABNQAECn8oAAMQAAoKjx03HQCwAgAQAAkKjx03HQCwAgARAAEKAACOdgAhAAAAAA==.Balfazar:BAAANQAECgYIDAAAAA==.Banilibug:BAAANQAECggIEgAAAA==.Baraddur:BAAANQADCgQIBgAAAA==.Baradun:BAAANQAECgUIBwAAAA==.Barrymanalow:BAABNQAECn8pAAIBAAkKcQcDPABKAQABAAkKcQcDPABKAQAAAA==.',
Be='Beachmouse:BAAANQADCgYIBgABNQAECgEJAQAKAAAAAA==.Bearclaw:BAAANQADCgUIBQAAAA==.Beorngoat:BAAANQAECgUICgAAAA==.Bernarn:BAAANQADCgQIBAAAAA==.',
Bi='Bigidiot:BAAANQAECgQIBAAAAA==.',
Bl='Blackout:BAABNQAECn8hAAMSAAkK0CCVBgAGAgASAAkKMyCVBgAGAgATAAIKEBt13wCUAAABNQAECgoKOwAQABAbAA==.Bloodpool:BAAANQAECgIIAgAAAA==.Bluerabbit:BAAANQAECgEIAgABNQAECgoKMgAFAAclAA==.',
Bo='Bobbybrady:BAAANQADCgUICgAAAA==.Bokni:BAAANQAECgIIAgAAAA==.',
Br='Brayk:BAAANQADCgIIAgAAAA==.',
Bu='Bufforc:BAAANQADCgYIBgAAAA==.Buildie:BAAANQADCgcIBwAAAA==.Bushwhacker:BAAANQAECgYIBwAAAA==.Butterbean:BAABNQAECn8nAAIUAAoK4Rm/QQClAgAUAAoK4Rm/QQClAgAAAA==.',
Ca='Calice:BAAANQADCgMIAwAAAA==.Cappally:BAAANQADCgUIBgAAAA==.Carch:BAEANQADCgUIBQAAAA==.Cashinout:BAAANQAECggIAwABNQAECggIBwAKAAAAAA==.',
Ch='Charizard:BAAANQAECggIAgAAAA==.Chickenhawk:BAAANQAECgQIEAAAAA==.Chicxulub:BAAANQADCgcIDAAAAA==.Chonkyninja:BAAANQAECgQJBAAAAA==.Choroksaek:BAAANQADCggIJAAAAA==.',
Ci='Citan:BAABNQAECn8aAAIMAAkKdRUzIQDXAQAMAAkKdRUzIQDXAQAAAA==.',
Cl='Classfantasy:BAABNQAECn8uAAMVAAoK1RkENgD9AQAVAAkK2hoENgD9AQAJAAYKrQZ40ADGAAAAAA==.',
Co='Condesate:BAAANQAECgcIBwAAAA==.Convict:BAAANQAECgEIAQABNQAECgoKFAAMAEgSAA==.Cool:BAAANQAECggIBwAAAA==.',
Cr='Crazytoe:BAAANQAECgEIAQAAAA==.Croghon:BAAANQAECgIIAgAAAA==.',
Ct='Cthruthyveil:BAAANQAECgUIEwAAAA==.',
Cu='Cursè:BAAANQABCgIIAgABNQAECggIBwAKAAAAAA==.',
Cy='Cythrandir:BAAANQAECgQIDAABNQAFFAQICgAIACUTAA==.',
Da='Dany:BAAANQAECgQIBQAAAA==.Darkriff:BAAANQABCggIEQAAAA==.Daruta:BAAANQADCgQIBgAAAA==.Daytona:BAAANQAECgcIDwAAAA==.',
Dd='Ddccssff:BAABNQAECn8XAAIIAAgK4AoXJQFOAQAIAAgK4AoXJQFOAQAAAA==.',
De='Deathcoiled:BAAANQAECgIIAgAAAA==.Dethrahzen:BAAANQAECgEIAgAAAA==.',
Di='Dindunuthin:BAAANQAECgMIBAAAAA==.Dipika:BAAANQAECgQICAAAAA==.Disektor:BAABNQAECn8gAAIWAAkKWhQrjAD+AQAWAAkKWhQrjAD+AQAAAA==.',
Dk='Dkray:BAABNQAECn8sAAMHAAcKbQdcXQDMAAAHAAcKBgdcXQDMAAAMAAUKUAa3nADEAAAAAA==.',
Do='Donnettlen:BAAANQADCgcICAAAAA==.Donorli:BAAANQADCgYIBgAAAA==.Dotsfordayz:BAAANQAECgEIAwABNQAECgEIAQAKAAAAAA==.Douglit:BAAANQAECgQIBAAAAA==.',
Dr='Dronesworn:BAAANQADCgUICgAAAA==.Drstránge:BAAANQAECgQIBgAAAA==.',
Du='Dugatotems:BAABNQAECn8sAAMJAAoKnRWybADFAQAJAAoKnRWybADFAQAVAAkKDgqueQC1AQAAAA==.Dunkle:BAABNQAECn8xAAIWAAoKThv/UACXAgAWAAoKThv/UACXAgAAAA==.Duskhawk:BAABNQAECn8xAAMUAAkKHAfMpQBnAQAUAAkKHAfMpQBnAQAXAAIKWwE/gQBBAAAAAA==.',
Dy='Dynxy:BAAANQADCgYIBgAAAA==.',
Eb='Ebonise:BAAANQAECgQIBAABNQAECgUIEwAKAAAAAA==.',
Ed='Edrelang:BAAANQAECgMIAQAAAA==.',
El='Elivien:BAAANQADCgIIAgABNQADCgYIBgAKAAAAAA==.Ellechero:BAAANQAECgIIAQAAAA==.Elthador:BAAANQADCgQIBAAAAA==.',
Eo='Eogimboonn:BAAANQADCgYIBgAAAA==.',
Er='Eredin:BAAANQADCgMIAwAAAA==.Erinna:BAAANQAECgIIAgAAAA==.Erommêl:BAAANQAECgQIBAAAAA==.',
Fa='Fafner:BAAANQADCgEIAQAAAA==.Farsha:BAAANQADCgYIBgAAAA==.',
Fe='Fextrius:BAABNQAECn86AAIWAAoKcx0yJgCoAgAWAAoKcx0yJgCoAgAAAA==.',
Fr='Frthckr:BAAANQADCgIIAgAAAA==.',
Fu='Funnelcakes:BAAANQADCgEIAQAAAA==.',
Ga='Garreux:BAAANQADCgIIAQAAAA==.Garroc:BAAANQAECgQICAAAAA==.Gazebo:BAAANQADCgUICwAAAA==.',
Ge='Genghis:BAAANQAECggIAgAAAA==.',
Gh='Ghast:BAABNQAECn9UAAMTAAoKyA56hgDWAQATAAoKUg56hgDWAQAYAAIKqRPlYABjAAAAAA==.',
Gi='Giddley:BAAANQABCgMIAwAAAA==.Gigaflare:BAABNQAECn8yAAMZAAoKfxA1DQDFAQAZAAoKfxA1DQDFAQAIAAgKHwXZDAF3AQAAAA==.',
Gl='Gladîator:BAAANQADCgEJAQAAAA==.Glahmgold:BAAANQAECgcIDgAAAA==.',
Go='Goatale:BAABNQAECn9GAAIaAAoKPx7cDgBvAgAaAAoKPx7cDgBvAgAAAA==.Goathunt:BAAANQADCggICAABNQAECgoKRgAaAD8eAA==.Goatseer:BAABNQAECn8ZAAIPAAgKQhg8EgBGAgAPAAgKQhg8EgBGAgAAAA==.Goatwizard:BAAANQAECgMIBAAAAA==.Gobblynn:BAAANQADCggIFgAAAA==.Goldvalkyrie:BAAANQADCggIDQAAAA==.Goodspeed:BAAANQAECgQIBAAAAA==.',
Gr='Grandpawolf:BAAANQAECgYIDAAAAA==.Graymoon:BAAANQADCgQICAAAAA==.Greywings:BAAANQAECgUICAAAAA==.Grimnaw:BAAANQADCgcIDgAAAA==.Grimroxs:BAABNQAECn8sAAIbAAkK7QhsbwBbAQAbAAkK7QhsbwBbAQAAAA==.Griptape:BAABNQAECn8bAAMHAAcK2BEsWgCKAQAHAAcK2BEsWgCKAQAMAAEKAACG+QAeAAABNQAECgEIAQAKAAAAAA==.',
Gu='Guylapso:BAAANQADCgYIEwAAAA==.',
['Gå']='Gålahad:BAAANQAECgEIAQAAAA==.',
Ha='Hairydragon:BAAANQAECgQIBAABNQAECgoKRgAaAD8eAA==.Handerbug:BAABNQAECn8yAAMFAAoKByX9AgDOAwAFAAoKByX9AgDOAwAGAAEKAACXTwBkAAAAAA==.Handiebug:BAAANQADCgYIBgABNQAECgoKMgAFAAclAA==.Handybug:BAAANQAECgEIAQABNQAECgoKMgAFAAclAA==.',
He='Healtaxi:BAAANQAECgEIAQAAAA==.Heiler:BAABNQAECn8pAAIDAAkKHAzVcwCAAQADAAkKHAzVcwCAAQAAAA==.',
Hi='Hi:BAAANQAECgUICQAAAA==.',
Ho='Hogglethorp:BAAANQAECgIIAgAAAA==.Hokis:BAAANQADCgcIBwAAAA==.Holyhooters:BAAANQADCggIEwAAAA==.Horns:BAABNQAECn8fAAIUAAoKUg2IXgALAgAUAAoKUg2IXgALAgAAAA==.Hornshatter:BAABNQAECn8tAAMcAAkKwg8lGgChAQAcAAkKwg8lGgChAQACAAUKLgR8agF1AAAAAA==.',
Hr='Hruroth:BAAANQADCgMIBAAAAA==.',
Ia='Iamevil:BAAANQAECgMIBAAAAA==.',
Ib='Ibis:BAAANQADCgUIBQAAAA==.',
Id='Idontrez:BAAANQAECggICQAAAA==.',
Ig='Igbbmn:BAAANQADCgIIAgAAAA==.Igh:BAAANQAECgcIDQAAAA==.',
Il='Illadron:BAABNQAECn8UAAIdAAkK4BoADAAKAgAdAAkK4BoADAAKAgAAAA==.',
In='Inala:BAAANQAECgUIDAAAAA==.Infuzed:BAABNQAECn87AAIQAAoKEBtqGwC+AgAQAAoKEBtqGwC+AgAAAA==.',
Io='Iove:BAABNQAECn8fAAIDAAoK/RlRXwDDAQADAAoK/RlRXwDDAQAAAA==.',
Ir='Ironface:BAAANQADCgQIBAAAAA==.',
It='Itsmykitty:BAAANQABCgIIAgABNQAECggIBwAKAAAAAA==.',
Ja='Jacksus:BAABNQAECn8iAAIMAAoK2hxVEAB+AgAMAAoK2hxVEAB+AgABNQAFFAMIBgAWACkiAA==.',
Jd='Jdbud:BAAANQAECgQIBAAAAA==.Jdpot:BAABNQAECn8YAAIVAAcKkAi8oQDDAAAVAAcKkAi8oQDDAAAAAA==.',
Je='Jenaaidy:BAABNQAECn8pAAIBAAoKRBHRGADcAQABAAoKRBHRGADcAQAAAA==.Jesko:BAAANQADCgUICAAAAA==.',
Ji='Jimmies:BAAANQABCgMIBQAAAA==.',
Jo='Joedavola:BAAANQAECgQIBgAAAA==.Jooshie:BAAANQAECgMIBgABNQAECgoKGAAeAOshAA==.Jooshy:BAABNQAECn8kAAIfAAkKByIDBQBdAwAfAAkKByIDBQBdAwABNQAECgoKGAAeAOshAA==.Josher:BAAANQADCgEIAQABNQAECgoKGAAeAOshAA==.Joshieboba:BAABNQAECn8YAAIeAAoK6yGHCQAtAwAeAAoK6yGHCQAtAwAAAA==.Joyzee:BAAANQADCgcIEQAAAA==.',
Ju='Judge:BAABNQAECn8jAAICAAcKhAus/wDqAAACAAcKhAus/wDqAAAAAA==.Justviolence:BAAANQADCggIEAAAAA==.',
Jy='Jynrokka:BAABNQAECn81AAIHAAkKViC0FwBIAgAHAAkKViC0FwBIAgAAAA==.',
Ka='Kanati:BAAANQADCgUIBQAAAA==.Katasaria:BAACNQAFFH8OAAIWAAUKihBkHgDIAAAWAAUKihBkHgDIAAA1AAQKfzQAAhYACgq1In4oABgDABYACgq1In4oABgDAAAA.Katiebug:BAAANQADCggIGwAAAA==.Katiekat:BAAANQADCgQIBgAAAA==.Kaycee:BAAANQADCgEIAQABNQAECgEIAQAKAAAAAA==.Kayceedilla:BAAANQADCgQIBAABNQAECgEIAQAKAAAAAA==.Kaycer:BAAANQAECgEIAQAAAA==.',
Ke='Keeps:BAAANQAECgQIBAAAAA==.Kelsey:BAAANQAECgIIAgAAAA==.Kerl:BAAANQADCgYIBgAAAA==.Kestrell:BAABNQAECn8lAAQgAAkKIxEzDgBkAQAgAAkKExAzDgBkAQAfAAYKfQfZNwDWAAAhAAUKkgrtGQCgAAAAAA==.Kevoni:BAAANQADCgMIAwAAAA==.',
Kh='Khorlock:BAAANQAECgQIDwAAAA==.Khorus:BAABNQAECn8bAAICAAcKixWCuACtAQACAAcKixWCuACtAQAAAA==.',
Ki='Kirana:BAAANQAECgYIEAAAAA==.',
Ko='Koalateectrl:BAAANQADCgUIBQAAAA==.',
Kr='Kravin:BAAANQAECgYIDQAAAA==.Krysnya:BAAANQAECgcIDQAAAA==.',
Ku='Kudrani:BAAANQADCgQIBwABNQADCgYIBgAKAAAAAA==.',
Ky='Kynnas:BAABNQAECn8zAAIRAAoK+w9hIQBBAgARAAoK+w9hIQBBAgAAAA==.',
La='Laneywine:BAAANQABCgEIAQAAAA==.Larinas:BAAANQAECgIIAwAAAA==.Larlifax:BAAANQAECgEIAQAAAA==.Lauxy:BAAANQAECgcICgAAAA==.',
Le='Leonuss:BAACNQAFFH8GAAIWAAMKKSIpIAC+AAAWAAMKKSIpIAC+AAA1AAQKfz0AAhYACgpsJssIAK0DABYACgpsJssIAK0DAAAA.Levìstus:BAABNQAECn8uAAINAAkKARnNJwAaAgANAAkKARnNJwAaAgAAAA==.Leylaní:BAABNQAECn8vAAIUAAkKQBKldQAkAgAUAAkKQBKldQAkAgAAAA==.',
Li='Lidria:BAAANQADCggIDQAAAA==.Lillinth:BAAANQAECgUICgABNQAFFAMIBgAWACkiAA==.Lilmagedude:BAAANQAECgIIBAAAAA==.Lilmissblue:BAAANQADCgcIBwAAAA==.Linoir:BAABNQAECn8xAAICAAoKCSCwKgAcAwACAAoKCSCwKgAcAwAAAA==.Livenasty:BAAANQAECgUIBwABNQAECggIBwAKAAAAAA==.',
Lo='Loroessan:BAAANQAECggIEAAAAA==.',
Lu='Lucylawladin:BAAANQAECgYICAAAAA==.Lurry:BAAANQADCgQIBAAAAA==.',
Ly='Lykios:BAAANQADCgYIBgAAAA==.Lythea:BAAANQAECgYICQABNQAECgoKPwAgAFohAA==.Lytheum:BAABNQAECn8/AAIgAAoKWiF1BABUAwAgAAoKWiF1BABUAwAAAA==.',
Ma='Maatato:BAAANQADCgQIBAAAAA==.Magikon:BAAANQADCgEIAQAAAA==.Magista:BAAANQAECgUIBQAAAA==.Maitias:BAAANQAECgQIBAABNQAECgMIAwAKAAAAAA==.Malachar:BAABNQAECn81AAIOAAkKfg+fGABGAQAOAAkKfg+fGABGAQAAAA==.Malboro:BAABNQAECn8fAAMYAAkKyAzTFADHAQAYAAkK6AvTFADHAQATAAMKAgwa0ACxAAAAAA==.Maled:BAABNQAECn8hAAQSAAoKbwm4EgAeAQASAAgK7Ai4EgAeAQAYAAMKbgpuHQB9AAATAAIKogRKMQFZAAAAAA==.Maloa:BAAANQADCgUIBQABNQAECgkJNQAFAKwZAA==.',
Me='Meldin:BAABNQAECn8iAAIUAAoKHxosMwB6AgAUAAoKHxosMwB6AgAAAA==.Mennia:BAAANQAECgQIBAAAAA==.Method:BAABNQAECn80AAMcAAoKshFuGwCWAQAcAAoKshFuGwCWAQACAAIKYAy5sgEuAAAAAA==.',
Mi='Miannya:BAABNQAECn8jAAIaAAkKrBstFgCeAgAaAAkKrBstFgCeAgAAAA==.Mignons:BAAANQAECgQIBAAAAA==.Mikuohashi:BAAANQAECgYICQAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mineos:BAAANQAECgQIDwAAAA==.Minipedro:BAAANQAECgUICAAAAA==.Miracleman:BAAANQAECgMIAwAAAA==.Mirmidon:BAAANQABCggIEgAAAA==.Missingparts:BAAANQAECgQICQAAAA==.Mistamiso:BAAANQAECggIEwABNQAECgoKOwAQABAbAA==.Mistrmiso:BAAANQADCgEIAQABNQAECgoKOwAQABAbAA==.',
Mm='Mmandalorian:BAAANQADCgQIBAAAAA==.',
Mo='Moahuntress:BAAANQADCgUICQAAAA==.Moonlyt:BAAANQADCggIGQAAAA==.Morgaine:BAAANQADCggIJwABNQAECgUIEgAKAAAAAA==.Morn:BAABNQAECn80AAIgAAoKCRreEABIAgAgAAoKCRreEABIAgAAAA==.Mostachito:BAAANQADCgMIAwAAAA==.',
Mu='Mundory:BAAANQADCgQIBAAAAA==.Mutalation:BAABNQAECn8oAAIIAAkKSgWvuQAyAQAIAAkKSgWvuQAyAQAAAA==.',
My='Myra:BAAANQADCgMIAwAAAA==.Mystu:BAAANQAECgUIBAAAAA==.',
Na='Nadià:BAAANQAECgUIEQAAAA==.',
Ne='Needagrip:BAABNQAECn8vAAIHAAkKNxcmKgCxAQAHAAkKNxcmKgCxAQAAAA==.Neonn:BAAANQABCgEIAQAAAA==.Netherid:BAAANQADCgQIBgAAAA==.',
Ni='Nidwick:BAAANQADCgIIAgAAAA==.Nifin:BAAANQAECgUIDwAAAA==.',
No='Notrobo:BAAANQAECgYICgABNQAFFAUIDgAWAIoQAA==.',
Ny='Nystannia:BAAANQADCgEIAQABNQADCgYIBgAKAAAAAA==.',
On='Onyx:BAAANQADCgMIAwAAAA==.',
Oo='Oor:BAAANQAECgQIAwABNQAECgoKQAAJACIeAA==.Oormoonmoon:BAAANQADCggICAAAAA==.',
Or='Orannir:BAAANQADCgQIBAAAAA==.Orgrym:BAAANQAECgQIBQAAAA==.Orialis:BAAANQADCgYIBQAAAA==.Orlandbro:BAABNQAECn8qAAMXAAoK9RgoFgDmAQAXAAoKORYoFgDmAQAUAAMKoh4eEAHlAAAAAA==.',
Os='Oshiokiyo:BAAANQADCggIOQAAAA==.',
Pa='Patchs:BAAANQAECgUIBwAAAA==.Pawradox:BAABNQAECn9JAAIBAAoKMRZgEgA1AgABAAoKMRZgEgA1AgAAAA==.',
Pe='Peeves:BAAANQADCgMIAgABNQAECgoKMgAFAAclAA==.',
Ph='Phenomenon:BAABNQAECn9SAAIUAAoKKSC6HADOAgAUAAoKKSC6HADOAgAAAA==.',
Pi='Pitviper:BAAANQADCgIIAgAAAA==.',
Pl='Plina:BAABNQAECn8rAAICAAkK6BTykgCmAQACAAkK6BTykgCmAQAAAA==.',
Po='Ponglenis:BAAANQAECgQIBwABNQAECggIBwAKAAAAAA==.Portalmaster:BAAANQADCgIJAgAAAA==.Poshiesty:BAABNQAECn8qAAIaAAoKOxjHEwApAgAaAAoKOxjHEwApAgAAAA==.Potatofox:BAAANQADCggICgAAAA==.Potatolor:BAABNQAECn8cAAIiAAkKVBKKIACHAQAiAAkKVBKKIACHAQAAAA==.',
Pr='Presto:BAAANQADCgMIAwAAAA==.',
Pu='Pulli:BAAANQADCgQIBAAAAA==.Pusinmyboot:BAAANQADCgEIAQAAAA==.',
Pv='Pve:BAABNQAECn89AAMjAAoKZyLSAACSAwAjAAoKZyLSAACSAwAUAAEKMxFPTgFEAAAAAA==.',
Py='Pyx:BAAANQAECgUIBQAAAA==.',
Ra='Raehanji:BAAANQADCgQICgAAAA==.Raiina:BAACNQAFFH8FAAIJAAIK9hA+JACCAAAJAAIK9hA+JACCAAA1AAQKfzUAAgkACgr1Glc5AHkCAAkACgr1Glc5AHkCAAAA.Rains:BAABNQAECn8WAAIIAAYKThUJ7wCsAQAIAAYKThUJ7wCsAQAAAA==.Raora:BAAANQAECgQIBQAAAA==.Rathane:BAABNQAECn9NAAIUAAoKbByIKgCXAgAUAAoKbByIKgCXAgAAAA==.Razhj:BAAANQADCgIIAgAAAA==.',
Re='Reapr:BAABNQAECn8vAAINAAkKxRdKMQAdAgANAAkKxRdKMQAdAgAAAA==.Redrabbit:BAAANQAECgIIAgAAAA==.Reikpord:BAAANQADCggICAAAAA==.Rexx:BAAANQADCgYICgAAAA==.',
Rh='Rhapsody:BAABNQAECn81AAIkAAkK3SU1BQDLAwAkAAkK3SU1BQDLAwAAAA==.',
Ri='Rizzwan:BAAANQAECgQIBQAAAA==.',
Ro='Robotkirky:BAAANQAECgQIBAAAAA==.',
Ru='Runecleaver:BAABNQAECn9AAAIJAAoKIh6PMACfAgAJAAoKIh6PMACfAgAAAA==.Ruw:BAABNQAECn8kAAIlAAoKwRMrHABDAQAlAAoKwRMrHABDAQAAAA==.Ruwmage:BAAANQADCggICAAAAA==.',
Sa='Sardroth:BAABNQAECn87AAMMAAoKqiNcCQB0AwAMAAoKqiNcCQB0AwANAAIK5hOjlQBqAAAAAA==.Satavara:BAAANQAECgQICgAAAA==.',
Se='Seiba:BAAANQABCgMIAwAAAA==.',
Sh='Shapòópy:BAAANQAECgYIEAAAAA==.Sharius:BAAANQAECggIBwAAAA==.Shavv:BAAANQADCgQIBgAAAA==.Shawesome:BAAANQADCggICAAAAA==.Shiera:BAABNQAECn8WAAMZAAkKvw7CDwCsAQAZAAgKvw7CDwCsAQAIAAYKngW+SAEVAQAAAA==.Shockyghost:BAAANQADCggICAAAAA==.',
Si='Sightlightx:BAABNQAECn8bAAMiAAgKuxcwEAARAgAiAAgKuxcwEAARAgAaAAIKrQhDYQBaAAAAAA==.Sigs:BAAANQADCgYIBgAAAA==.Silvershine:BAAANQADCggICwAAAA==.Siryn:BAAANQAECgYICgAAAA==.',
Sl='Slaphaschel:BAAANQADCgMIAwAAAA==.',
Sm='Smallest:BAAANQADCgEIAQABNQAECgEIAQAKAAAAAA==.',
Sn='Sneakygoat:BAAANQAECgcIDgABNQAECgoKRgAaAD8eAA==.',
Sp='Sparkelynn:BAAANQADCgQIBgAAAA==.Spinlock:BAAANQADCgQIBAAAAA==.Spitfyre:BAAANQADCggICwAAAA==.',
Sq='Squeeze:BAAANQADCgMJAwAAAA==.',
St='Stonehammer:BAAANQADCgUIBgAAAA==.',
Su='Susa:BAAANQADCgMIBAAAAA==.',
Sy='Sylesta:BAABNQAECn8wAAMeAAoKyhX5FwBYAgAeAAoKyhX5FwBYAgAFAAYKdhEJYgBGAQAAAA==.Syrden:BAAANQADCggIDAABNQAECgoKMgAeADAOAA==.Syribo:BAAANQABCgIIAgAAAA==.',
Ta='Talís:BAAANQAECgcIDgAAAA==.Tancia:BAAANQAECgIIAwAAAA==.Taranis:BAABNQAECn8pAAMVAAkKEw8TlgBtAQAVAAcKVAoTlgBtAQAJAAgKNAwtcABjAQAAAA==.Taverrek:BAAANQADCggICgAAAA==.',
Te='Teremen:BAAANQADCgUICQABNQAFFAkJFAABAFUXAA==.',
Th='Thandas:BAAANQADCgYIDQAAAA==.Theherooz:BAAANQAECggIDAAAAA==.Thekarens:BAAANQAECgQICAAAAA==.Thniper:BAABNQAECn8tAAIXAAoKchryGgB9AgAXAAoKchryGgB9AgAAAA==.Thoriumaster:BAAANQADCgcIBwAAAA==.',
Ti='Tiamaria:BAABNQAECn8pAAIkAAkK2w4hWwAHAgAkAAkK2w4hWwAHAgAAAA==.',
Tr='Trick:BAAANQADCgYIBgAAAA==.Trilbey:BAAANQADCgYICwAAAA==.Trismegistus:BAAANQADCgcICgAAAA==.',
Tw='Twittch:BAAANQABCgEIAQAAAA==.',
Ty='Tyinithyr:BAAANQAECgUIBQABNQAFFAkJFAABAFUXAA==.Tyinviril:BAACNQAFFH8UAAIBAAkKVRdtAgBqAgABAAkKVRdtAgBqAgA1AAQKf10AAwEACgpqJhUBAOEDAAEACgpqJhUBAOEDAAMABwpJFnNcAM0BAAAA.Tyrandice:BAAANQAECgIIAwABNQAECggIBAAKAAAAAA==.Tythoruin:BAAANQAECgMIAwABNQAFFAkJFAABAFUXAA==.Tyvireth:BAAANQADCggIDgABNQAFFAkJFAABAFUXAA==.',
Va='Varlund:BAAANQABCgEIAQAAAA==.',
Ve='Veraz:BAABNQAECn9DAAMCAAoKxB87LgAPAwACAAoKxB87LgAPAwAkAAcKbAyAjwBvAQAAAA==.',
Vo='Vonawesome:BAAANQAECggIEQAAAA==.Vorpalblade:BAABNQAECn8yAAIOAAoK2xIAEQCnAQAOAAoK2xIAEQCnAQAAAA==.',
Vy='Vylas:BAAANQADCgEIAQAAAA==.Vyraal:BAAANQAECgUIDwAAAA==.',
Wa='Warloque:BAAANQADCgUIEAAAAA==.Warlorok:BAAANQADCgYIBgAAAA==.Warpsmithoor:BAAANQAECgYIBwABNQAECgoKQAAJACIeAA==.',
We='Wend:BAABNQAECn9KAAMmAAoKVyDKAAAvAwAmAAoKVyDKAAAvAwAIAAEK8QvdWgE3AAAAAA==.Weywey:BAABNQAECn8jAAIUAAkKuwzYlACLAQAUAAkKuwzYlACLAQAAAA==.',
Wh='Whisperspeak:BAAANQABCgEIAQAAAA==.',
Wo='Wobblerslock:BAAANQADCgQICAABNQADCgcICQAKAAAAAA==.',
Wr='Wram:BAAANQAECgUIEgAAAA==.Wreckamma:BAAANQAECgcICgABNQAECgcIGwACAIsVAA==.Wreckturd:BAAANQAECgYIEQABNQAECgcIGwACAIsVAA==.Wreckuiem:BAAANQAECgYICQABNQAECgcIGwACAIsVAA==.',
Wy='Wychlord:BAAANQAECgEIAQAAAA==.Wylder:BAABNQAECn8bAAMGAAgKUhIgJwBNAQAGAAgKUhIgJwBNAQAFAAUKUAM2iQCvAAAAAA==.',
Xe='Xenophilious:BAABNQAECn8eAAICAAYKHQkKBAEYAQACAAYKHQkKBAEYAQAAAA==.',
Xi='Xiomara:BAAANQADCgQIBgAAAA==.Xiøn:BAAANQAECgIIAgAAAA==.',
Xz='Xzahchky:BAAANQAECgMIBAAAAA==.',
Yn='Yn:BAAANQADCgIIAgAAAA==.',
Ze='Zelios:BAAANQADCgYIBgAAAA==.',
Zo='Zoemarie:BAAANQAECgEIAQAAAA==.Zoinx:BAABNQAECn8uAAITAAkKbh4ZQgCMAgATAAkKbh4ZQgCMAgAAAA==.',
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
