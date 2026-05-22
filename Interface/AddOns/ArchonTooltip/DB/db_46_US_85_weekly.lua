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

local lookup = {'Monk-Windwalker','Shaman-Elemental','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Hunter-BeastMastery','Priest-Discipline','Monk-Mistweaver','Shaman-Enhancement','DemonHunter-Vengeance','Priest-Holy','Rogue-Outlaw','Paladin-Protection','Shaman-Restoration','Druid-Feral','Warrior-Arms','Hunter-Marksmanship',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alaìrn:BAAALgAECgUJCwAAAA==.Alenciann:BAAALgAECgMJBwAAAA==.Alys:BAABLgAECn8mAAIBAAgJowgRKQAeAQABAAgJowgRKQAeAQAAAA==.',
Am='Amaniatres:BAAALgAECgQJCAAAAA==.Ammartin:BAAALgAECgEJAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgQJBAAAAA==.Angrylizard:BAAALgAECgEJAQAAAA==.Anklebiterr:BAAALgAECgUJBgAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgcJCAAAAA==.Ariiana:BAAALgAECgcJBwAAAA==.',
As='Asapshocky:BAACLgAFFH8MAAICAAQJMBhFEAA+AQACAAQJMBhFEAA+AQAuAAQKfywAAgIACAlnIhQIAJgCAAIACAlnIhQIAJgCAAAA.Asclepios:BAAALgAECgMJAwAAAA==.Asmoday:BAAALgADCgEJAQAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Balaris:BAAALgADCgcJBwABLgAECgcJEAADAAAAAA==.Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJBQAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgADAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Bellabelle:BAAALgADCggJFAAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAAALgAECgUJCAAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgUJBwADAAAAAA==.',
Bi='Biggiepants:BAABLgAECn8YAAMEAAgJexrBRABqAQAEAAgJ9g7BRABqAQAFAAcJeh3zLwBQAQAAAA==.Bighead:BAAALgADCgUJCwABLgAFFAMJBwABALYHAA==.Bigwarlocks:BAAALgAECgMJBwABLgAFFAMJBwABALYHAA==.Bintje:BAAALgADCgcJEgAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgQJBQAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECgkJEQAFACUcAA==.Bootyßandaid:BAAALgAECgcJBwAAAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJBQAAAA==.',
Bu='Buckis:BAAALgAECgUJCwAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgIJAgAAAA==.',
Ca='Cajia:BAABLgAECn8dAAMGAAgJoQkKEwDSAAAHAAgJDwioZwAwAQAGAAYJBgsKEwDSAAAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAIAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgAECgIJAgAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Choggy:BAABLgAECn8lAAIJAAgJahowEAALAgAJAAgJahowEAALAgAAAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgIJBAABLgAFFAMJBwABALYHAA==.',
Cr='Crinklecut:BAAALgAECggJEwAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMKAAkJsCI4AwBlAwAKAAkJsCI4AwBlAwALAAUJMho8NgBjAQAAAA==.Deadybear:BAAALgADCgcJCQABLgAECggJPwAMAEgUAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAINAAkJhCUtBAAwAwANAAkJhCUtBAAwAwAAAA==.',
Do='Donnabb:BAAALgAECgYJCwAAAA==.Doran:BAAALgAECgUJDQAAAA==.Doriathrin:BAAALgADCgcJCwAAAA==.Doujinshi:BAABLgAECn8OAAIEAAcJIBziUwCoAQAEAAcJIBziUwCoAQAAAA==.',
Dr='Draedis:BAAALgAECgMJCAAAAA==.Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJBQAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgADAAAAAA==.Dragonname:BAAALgAECgEJAQAAAA==.Drakoil:BAABLgAECn8hAAMOAAgJ2xQBCABuAQAOAAcJpxIBCABuAQAPAAcJRQ5dNQAEAQAAAA==.Dreademperor:BAACLgAFFH8JAAIQAAQJdBXfDQD/AAAQAAQJdBXfDQD/AAAuAAQKfyYAAxAACQnUHfAEAPYCABAACQnUHfAEAPYCABEABAlDDwdFAN0AAAEuAAUUBQkMABIAJR8A.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8MAAISAAUJJR9JCABsAQASAAUJJR9JCABsAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJDAASACUfAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJDAASACUfAA==.Drenrah:BAABLgAECn8nAAITAAkJuw+CHgDCAQATAAkJuw+CHgDCAQAAAA==.Drgndeeznutz:BAACLgAFFH8KAAIUAAQJfhcmCQBXAQAUAAQJfhcmCQBXAQAuAAQKfyAAAhQACQn/HFcEANgCABQACQn/HFcEANgCAAAA.Drizz:BAAALgAECgIJAwAAAA==.Drunkenrage:BAACLgAFFH8iAAIVAAYJAyEUAwD0AQAVAAYJAyEUAwD0AQAuAAQKfx4AAhUACQkcIvsBAIIDABUACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgIJAgAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8qAAIJAAkJ0wWNJQBIAQAJAAkJ0wWNJQBIAQAAAA==.Elementdemon:BAAALgAECgQJBQAAAA==.',
En='Enthalpy:BAABLgAECn8cAAIWAAgJjxjEggDMAQAWAAgJjxjEggDMAQAAAA==.',
Er='Erazath:BAAALgAECgUJCAABLgAECgkJEAADAAAAAA==.',
Es='Esperzoa:BAAALgAECggJDQAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJDAASACUfAA==.',
Eu='Eucalicdes:BAABLgAECn81AAIXAAkJSBS8CgDQAQAXAAkJSBS8CgDQAQAAAA==.',
Ez='Ezra:BAAALgADCgYJBgAAAA==.',
Fa='Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJJQANAIclAA==.',
Fe='Felicity:BAACLgAFFH8WAAIYAAUJ2h2xCwBeAQAYAAUJ2h2xCwBeAQAuAAQKfzYAAxgACQmPIpIEAE4DABgACQmPIpIEAE4DABkABQmDDd8PAOIAAAAA.Ferendis:BAABLgAECn8nAAIEAAgJPSNnCwCzAgAEAAgJPSNnCwCzAgAAAA==.Fernard:BAAALgADCgYJBgABLgAECgkJEQAFACUcAA==.',
Fl='Florita:BAAALgADCgkJFgAAAA==.',
Fo='Fordinn:BAABLgAECn8hAAMQAAcJ7BRtHAACAQARAAcJxhJoNwAZAQAQAAUJsRRtHAACAQAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJBAAAAA==.Freemi:BAAALgAECgEJAQAAAA==.',
Fu='Fuddytwo:BAAALgAECgcJEQAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAECgkJMAAIAIokAA==.Gasket:BAACLgAFFH8GAAMaAAMJuxkNCADwAAAaAAMJdRMNCADwAAAbAAIJ9RhBfQCrAAAuAAQKfyMAAxsACQlnIsMiALQCABsACQlvIcMiALQCABoAAwmhH9ANABcBAAAA.Gauteng:BAAALgAECgIJAgABLgAFFAMJBQANAKMgAA==.',
Gh='Ghidõráh:BAAALgADCgkJEAAAAA==.Ghorac:BAAALgADCgYJCAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgQJBQAAAA==.Grit:BAAALgAECgYJBgAAAA==.Grögo:BAAALgADCgkJCQAAAA==.',
Gu='Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgAECgcJBwABLgAECgkJHgANAIQlAA==.Hark:BAACLgAFFH8GAAIcAAMJNQdcQAC/AAAcAAMJNQdcQAC/AAAuAAQKfyUAAhwACQkdGPc3AM4BABwACQkdGPc3AM4BAAAA.Harpin:BAAALgADCgEJAQAAAA==.Harvin:BAABLgAECn8rAAIMAAgJ/SGnAgD/AgAMAAgJ/SGnAgD/AgAAAA==.',
He='Hekus:BAAALgAECgcJDgAAAA==.Helanua:BAAALgAECggJEwAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippopotamus:BAAALgAECgIJAgAAAA==.Hit:BAAALgAECgUJCgAAAA==.',
Ho='Holytide:BAAALgAECgcJEwAAAA==.Hope:BAABLgAECn8XAAILAAcJcge3OgDNAAALAAcJcge3OgDNAAAAAA==.Horrorfang:BAABLgAECn8rAAIbAAgJRRoXLAAIAgAbAAgJRRoXLAAIAgAAAA==.',
Hu='Hukjo:BAAALgAECgcJEAAAAA==.',
Ib='Ibaar:BAACLgAFFH8VAAIPAAUJ/iPACwCgAQAPAAUJ/iPACwCgAQAuAAQKfysAAw8ACQm9I00HAAUDAA8ACAk0I00HAAUDAA4ABgneIAcNAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAABLgAECn8cAAMJAAgJmiA/CwDPAgAJAAgJmiA/CwDPAgAdAAQJPBW2NwDpAAABLgAECgkJJwAeAKIiAA==.',
Il='Illedren:BAABLgAECn8QAAIEAAgJwwc7kAAAAQAEAAgJwwc7kAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8YAAIEAAkJDiTxEwDhAgAEAAkJDiTxEwDhAgAAAA==.',
Is='Isabel:BAAALgAECgYJBgABLgAECgcJDwADAAAAAA==.',
It='Ithacus:BAABLgAECn8nAAIfAAkJSBBlCgCqAQAfAAkJSBBlCgCqAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jattao:BAAALgADCgEJAQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgADCgcJBgAAAA==.',
Ji='Jinnlee:BAAALgAECgQJBAAAAA==.Jinoo:BAABLgAECn8qAAICAAgJjB0UEAAiAgACAAgJjB0UEAAiAgAAAA==.Jinufan:BAAALgAECgUJBwABLgAFFAUJFQAPAP4jAA==.',
Jo='Joe:BAAALgAECgcJCQAAAA==.Jorek:BAABLgAECn8WAAIRAAkJ6RQsGgDNAQARAAkJ6RQsGgDNAQAAAA==.',
Ju='Jugulator:BAAALgADCgUJBgAAAA==.',
Ka='Kaihune:BAAALgADCgIJAgAAAA==.Kaiva:BAAALgAECgQJBgAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAAALgAECgYJEwAAAA==.Kavik:BAAALgAECggJEwAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAACLgAFFH8GAAISAAMJ5Q34GAC4AAASAAMJ5Q34GAC4AAAuAAQKfycAAxIACQmVEvMbACMBABIACQl2EvMbACMBABsAAwmYDUX8AIMAAAAA.Keemosaki:BAAALgAECgcJEQAAAA==.Keemõ:BAABLgAECn8XAAMEAAYJvw1ddADlAAAEAAYJ0wxddADlAAAgAAYJowmGFgCkAAAAAA==.Keflá:BAAALgAECgQJCQAAAA==.Keysersöze:BAAALgADCgYJBwAAAA==.',
Kh='Khaas:BAABLgAECn8tAAIbAAgJgQnmYQBbAQAbAAgJgQnmYQBbAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAAALgAECggJEwAAAA==.Kildurgan:BAAALgAECgQJDQAAAA==.Killawarlock:BAABLgAECn8ZAAQHAAgJDSBIUADXAQAHAAcJDSBIUADXAQAIAAEJAABSJwBUAAAGAAEJ/hAbcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAMJBwABALYHAA==.',
Kk='Kkain:BAAALgAECgIJBAAAAA==.',
Ko='Korihor:BAAALgAECggJDAAAAA==.',
Kr='Krestus:BAABLgAECn8RAAMFAAcJJRx4KwC/AAAEAAYJrxkZfgAvAQAFAAMJKSB4KwC/AAAAAA==.Krispy:BAABLgAECn8fAAMBAAgJKhKNGgCLAQABAAgJKhKNGgCLAQAeAAUJvgO5TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgAECgMJAwAAAA==.',
La='Laxus:BAAALgADCgcJDAABLgAECgkJGAAOAHkMAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIbAAcJkA+vewAiAQAbAAcJkA+vewAiAQAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBgAcAPMdAA==.Lightfallen:BAAALgAECgcJEQAAAA==.Liisara:BAABLgAECn8bAAIEAAgJZQgrZQAKAQAEAAgJZQgrZQAKAQAAAA==.Lily:BAABLgAECn8rAAIXAAgJIho8CgDaAQAXAAgJIho8CgDaAQAAAA==.Linadra:BAABLgAECn8iAAINAAgJ9Ql8cABBAQANAAgJ9Ql8cABBAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAACLgAFFH8FAAINAAMJoyDwKgApAQANAAMJoyDwKgApAQAuAAQKfycAAg0ACQkWJUgRAAYDAA0ACQkWJUgRAAYDAAAA.',
Ll='Llorsa:BAABLgAECn8rAAIhAAgJ0RIeGADDAQAhAAgJ0RIeGADDAQAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgAECgIJAgAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAABLgAECn8qAAINAAgJbw1MYgBhAQANAAgJbw1MYgBhAQAAAA==.',
Ma='Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgMJAwABLgAECgYJFQANABkNAA==.Makaria:BAAALgAECggJEAAAAA==.Malbisa:BAAALgAECgQJBAAAAA==.Malphoz:BAAALgADCggJCAAAAA==.Mandragora:BAAALgAECgUJCQAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Meko:BAAALgAECgUJBwAAAA==.Mew:BAAALgAECgEJAQAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAIBAAQJJwvYDwACAQABAAQJJwvYDwACAQAuAAQKfyAAAgEACQn2IBoJAOYCAAEACQn2IBoJAOYCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn8pAAIHAAgJSQhcYwA6AQAHAAgJSQhcYwA6AQAAAA==.Mildoo:BAABLgAECn8rAAIIAAkJBA+2BQC/AQAIAAkJBA+2BQC/AQAAAA==.Milkymoo:BAAALgAECgUJDwABLgAFFAcJJgAhACEUAA==.Millina:BAAALgADCgIJAgABLgAECggJJgABAKMIAA==.Minipal:BAAALgAECgYJCwAAAA==.Mixednuts:BAABLgAECn8nAAMeAAkJoiIGAgB6AwAeAAkJoiIGAgB6AwABAAYJKCCqHwDaAQAAAA==.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgYJBgAAAA==.Monq:BAABLgAECn8WAAMBAAgJdBYUGgCPAQABAAgJdBYUGgCPAQAVAAEJyAkqjQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
Mu='Murdrmittens:BAAALgADCgEJAQAAAA==.',
My='Mythion:BAABLgAECn8WAAMKAAcJvBk6LwCdAQAKAAcJvBk6LwCdAQALAAIJoQNlaAAxAAAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIbAAgJkBeMTgCQAQAbAAgJkBeMTgCQAQAAAA==.Nafari:BAAALgADCgkJEQAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8oAAMhAAgJAhkoFwDMAQAhAAgJAhkoFwDMAQAJAAUJZgi+QAC0AAAAAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAACLgAFFH8HAAIKAAMJzBK7JwDZAAAKAAMJzBK7JwDZAAAuAAQKfyIAAwoACAkII/EJAN4CAAoACAkII/EJAN4CAAsAAQllEtyAADAAAAAA.Neodin:BAAALgAECgUJDgAAAA==.Nephadin:BAAALgADCgUJAwAAAA==.Nerfed:BAAALgAECgUJCAAAAA==.Neviaa:BAABLgAECn8fAAIbAAgJLQs0YQBdAQAbAAgJLQs0YQBdAQAAAA==.',
Ni='Nickypoo:BAAALgAECgMJBQAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgUJBQAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEgAAAA==.',
Ob='Obsidiian:BAABLgAECn8UAAIiAAgJjRHLBgCOAQAiAAgJjRHLBgCOAQAAAA==.Obsidion:BAAALgAECgQJCgABLgAECgcJIQAQAOwUAA==.',
Od='Odie:BAAALgAECgYJCAAAAA==.',
On='Onlyfangs:BAABLgAECn8/AAMMAAgJSBTgCgDjAQAMAAgJSBTgCgDjAQAPAAUJNgb4UgCJAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.',
Pa='Padivyn:BAABLgAECn8UAAICAAgJihh7FwDVAQACAAgJihh7FwDVAQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.',
Pe='Peanads:BAAALgADCgcJCgAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAABLgAECn8XAAMKAAkJLBH6QQBAAQAKAAgJcg76QQBAAQALAAIJAQUgYABEAAAAAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn8rAAIRAAgJWh1REAAsAgARAAgJWh1REAAsAgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwADAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8nAAMJAAkJeRSfEwDiAQAJAAkJeRSfEwDiAQAhAAEJQgQHhQAsAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAIAPEbAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8dAAIcAAcJXhCNQACtAQAcAAcJXhCNQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAAALgAECgYJCwAAAA==.',
Ri='Rion:BAABLgAECn8XAAIWAAkJcBE/RADNAQAWAAkJcBE/RADNAQAAAA==.Ristvakbaen:BAABLgAECn8wAAQIAAkJiiQgAQCxAgAIAAgJRiUgAQCxAgAHAAkJaB2LGABXAgAGAAYJeiSaBADiAQAAAA==.',
Ro='Robynlee:BAABLgAECn8jAAIhAAgJZhJ/IwDKAQAhAAgJZhJ/IwDKAQAAAA==.Rogùe:BAAALgAECgIJBAAAAA==.Rosebelle:BAAALgADCgQJBAAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgADAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.',
Sc='Sceryna:BAABLgAECn8nAAINAAkJzBcvLAAHAgANAAkJzBcvLAAHAgAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgAECgMJAgABLgAECgUJCQADAAAAAA==.Scrmndemn:BAABLgAECn8cAAINAAcJ8Aa0jAAMAQANAAcJ8Aa0jAAMAQAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIbAAcJNhZmcACoAQAbAAcJNhZmcACoAQAAAA==.Serpent:BAACLgAFFH8JAAIQAAUJaRL5BwBQAQAQAAUJaRL5BwBQAQAuAAQKfyIAAhAACQm2HrwEAJICABAACQm2HrwEAJICAAAA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAECgkJMAAIAIokAA==.Sharaseth:BAAALgAECgYJDgAAAA==.Shikita:BAABLgAECn8rAAMKAAgJ0B51FQBVAgAKAAgJ0B51FQBVAgALAAEJHAZfigAlAAAAAA==.Shimadin:BAACLgAFFH8TAAINAAUJCRY9IwA+AQANAAUJCRY9IwA+AQAuAAQKfyYAAg0ACAmxH4YqAA8CAA0ACAmxH4YqAA8CAAAA.Shimpbizkit:BAAALgAECgUJDgABLgAFFAUJEwANAAkWAA==.Shimsong:BAAALgAECgYJCgABLgAFFAUJEwANAAkWAA==.Shmerek:BAABLgAECn8XAAIQAAkJPSAIBACrAgAQAAkJPSAIBACrAgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silenttits:BAAALgAECgEJAQAAAA==.Silverlumen:BAAALgAECgUJBgAAAA==.Silverstream:BAABLgAECn8oAAIKAAgJMRMdQgCZAQAKAAgJMRMdQgCZAQAAAA==.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAAALgADCgQJBAAAAA==.Slease:BAAALgADCgYJBgAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJCQABLgAECgkJHAAWAM8WAA==.Solitudé:BAABLgAECn8cAAMHAAgJCCTUFgBiAgAHAAcJAyHUFgBiAgAIAAUJpSVkCwA4AQABLgAFFAMJAwADAAAAAA==.Soteirian:BAABLgAECn8VAAMNAAYJGQ3mkwAAAQANAAYJGQ3mkwAAAQAjAAEJjwJnRQASAAAAAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgAECgEJAQAAAA==.Spider:BAABLgAECn8UAAIbAAcJQA1HcAA6AQAbAAcJQA1HcAA6AQAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAABLgAECn8XAAMCAAYJ9BIbMgAbAQACAAYJ9BIbMgAbAQAkAAUJRxWvTgAQAQAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQATAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgMJBQABLgAECgkJLwANABIkAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn8rAAIcAAgJ2xReNQC0AQAcAAgJ2xReNQC0AQAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8iAAIFAAkJPCWBAQAqAwAFAAkJPCWBAQAqAwAAAA==.Syriene:BAABLgAECn8YAAIlAAYJzg0PFgAAAQAlAAYJzg0PFgAAAQAAAA==.',
Ta='Tankhealz:BAAALgAECgMJBQAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQAAAA==.',
Te='Tecks:BAABLgAECn8XAAIhAAkJwgVGLQAYAQAhAAkJwgVGLQAYAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.',
Th='Theatrix:BAAALgAECgQJBAAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8eAAMmAAkJvxLPDADFAQAmAAkJphLPDADFAQARAAcJ/AhwTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8lAAINAAkJhyUAAgBfAwANAAkJhyUAAgBfAwAAAA==.Thsarus:BAABLgAECn8pAAMEAAgJZR+dFgBOAgAEAAgJZR+dFgBOAgAgAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIKAAkJmgQ9YADPAAAKAAkJmgQ9YADPAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBQAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAECgYJIQAGAGokAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8WAAIeAAUJShzqCQC8AQAeAAUJShzqCQC8AQAuAAQKfysAAx4ACQnQGFkTABQCAB4ACQnQGFkTABQCABUABAnxA0psAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8cAAIWAAkJzxZkRwDCAQAWAAkJzxZkRwDCAQAAAA==.',
Ug='Ugolok:BAAALgAECgUJCAAAAA==.',
Ur='Uriél:BAABLgAECn8aAAIEAAgJiyOmHwCTAgAEAAgJiyOmHwCTAgABLgAFFAMJAwADAAAAAA==.',
Va='Valeene:BAAALgAECgIJAgAAAA==.',
Ve='Veiler:BAABLgAECn80AAMcAAkJxw0FMQDGAQAcAAkJxw0FMQDGAQAnAAEJ3wH2lgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8nAAIWAAkJqAO9fQA/AQAWAAkJqAO9fQA/AQAAAA==.',
Vh='Vhye:BAAALgAECgYJCgAAAA==.',
Vi='Vinstalation:BAABLgAECn8qAAIaAAgJHBtXBgDEAQAaAAgJHBtXBgDEAQAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8iAAIcAAkJ7hPyLwDLAQAcAAkJ7hPyLwDLAQAAAA==.',
Vr='Vritraz:BAAALgAFFAMJAwAAAA==.Vrock:BAAALgAECgEJAQABLgAECggJHAAWAI8YAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAACLgAFFH8GAAIcAAMJLwHeUwCLAAAcAAMJLwHeUwCLAAAuAAQKfyAAAhwACQnVD15FAJsBABwACQnVD15FAJsBAAAA.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgMJBQAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgYJEQAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zaye:BAAALgAECgcJBwAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIbAAgJJhE+kwBZAQAbAAgJJhE+kwBZAQAAAA==.Zendonn:BAAALgAECgUJEQAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAISAAkJcRmFDADtAQASAAkJcRmFDADtAQAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMKAAkJ+RXSNwDIAQAKAAkJ+RXSNwDIAQALAAIJvwRldwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAAAAA==.',
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
