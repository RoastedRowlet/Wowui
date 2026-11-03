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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Paladin-Protection','Paladin-Retribution','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Assassination','Priest-Holy','Mage-Arcane','Rogue-Subtlety','Warlock-Destruction','Monk-Windwalker','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Warrior-Arms','Druid-Feral','Druid-Guardian','Hunter-BeastMastery','DeathKnight-Unholy','Rogue-Outlaw','Priest-Discipline','Hunter-Marksmanship','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aadrik:BAAANQADCggICAAAAA==.',
Ad='Adrenalin:BAAANQAECgYIEgAAAA==.Adversary:BAAANQADCgcICQAAAA==.',
Ae='Aennish:BAAANQADCgEIAQAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIEAAAAA==.',
Ai='Airibeth:BAAANQAECgMIAgAAAA==.Aiyanna:BAAANQAECgMIAwABNQAECgUIEAABAAAAAA==.',
Al='Alric:BAABNQAECn8zAAICAAoKyBmlDQBUAgACAAoKyBmlDQBUAgAAAA==.Althalos:BAAANQADCgEIAQAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQAECgYIBwAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Arator:BAAANQAECgEIAQAAAA==.Ardhammer:BAAANQAECggIDQAAAA==.Arragorn:BAABNQAECn8nAAIDAAoKUQ9iRwDDAQADAAoKUQ9iRwDDAQAAAA==.',
As='Asendra:BAAANQAECgQICAAAAA==.Astal:BAACNQAFFH8RAAMEAAYKeRgFBwArAQAEAAUKeRgFBwArAQAFAAEKAAAKKAAAAAA1AAQKfzIAAgQACgr8IqASAPkCAAQACgr8IqASAPkCAAAA.',
At='Ate:BAABNQAECn8kAAMGAAoKgxOCJwDkAQAGAAoKgxOCJwDkAQAHAAIKJQZNcQBJAAAAAA==.',
Au='Aurathur:BAABNQAECn8gAAMIAAgKzhZZGQBzAQAIAAgKzhZZGQBzAQAJAAEKAAAhpgE0AAAAAA==.',
Av='Avasilva:BAAANQADCgEIAQAAAA==.Avyl:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.',
Ay='Ayannar:BAAANQADCgMIAwAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECgcICgABAAAAAA==.Azriella:BAABNQAECn8bAAIKAAcKOwwjKAAHAQAKAAcKOwwjKAAHAQAAAA==.Azulina:BAAANQADCgEIAQAAAA==.Azuren:BAABNQAECn8xAAQLAAoK8QxKCwBzAQALAAoK8QxKCwBzAQAMAAIKkgUxGABAAAANAAEKngn7NwAkAAAAAA==.',
Ba='Bacon:BAABNQAECn9AAAMOAAoK4yDfGQDMAgAOAAoK4yDfGQDMAgAPAAEKlQjpKgAtAAAAAA==.Bamboozled:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.Bankai:BAABNQAECn8rAAIQAAkKnCO/BABFAwAQAAkKnCO/BABFAwAAAA==.',
Be='Beardedtroll:BAABNQAECn8UAAIRAAkKRR5JDQAaAwARAAkKRR5JDQAaAwAAAA==.Beefstrasz:BAACNQAFFH8RAAISAAYKOgUzDgB/AQASAAYKOgUzDgB/AQA1AAQKfzcAAhIACgpvFE9TACkCABIACgpvFE9TACkCAAAA.Beyla:BAABNQAECn8mAAIJAAoKxQ4ZbAC5AQAJAAoKxQ4ZbAC5AQAAAA==.',
Bh='Bhalecgos:BAAANQADCgYIEwAAAA==.',
Bi='Bishamon:BAAANQAECgIIBgAAAA==.',
Bl='Blank:BAAANQAECgMIAwAAAA==.Blazed:BAAANQAECgQIBQAAAA==.Blazethorn:BAAANQAECgEIAgAAAA==.Bleau:BAAANQAECgYIDQAAAA==.Blethings:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.Bloodhornbob:BAAANQADCgUIDwAAAA==.Bloodimary:BAAANQADCgIIAgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodráyne:BAAANQADCgMIAwAAAA==.Bloodymary:BAABNQAECn8/AAIFAAoKGhi7FgAqAgAFAAoKGhi7FgAqAgAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAABNQAECn87AAITAAoK1xQKRQAZAgATAAoK1xQKRQAZAgAAAA==.Bláze:BAAANQADCggICAABNQAECggIGwAUAAILAA==.Blôodräge:BAAANQAECgYICgAAAA==.',
Bo='Bomm:BAAANQAECgEIAgAAAA==.Boolzeye:BAAANQADCgEIAQAAAA==.Bouncy:BAAANQAECgIIAgAAAA==.Bowl:BAACNQAFFH8RAAIIAAYKqR0OAwAmAQAIAAYKqR0OAwAmAQA1AAQKfzUAAggACgryIqIIABMDAAgACgryIqIIABMDAAAA.',
Br='Branchling:BAAANQAECgcICwABNQAFFAcIGQATAEQSAA==.Breaklimit:BAAANQADCggIDgAAAA==.',
Bu='Burgi:BAAANQADCgIIAgABNQAECggIGgAVAFgOAA==.Butterkip:BAACNQAFFH8TAAIKAAYKKgyLBQAgAQAKAAYKKgyLBQAgAQA1AAQKfyYAAgoACgrBGx8YAJMCAAoACgrBGx8YAJMCAAAA.',
Ce='Cellan:BAAANQADCgYIFAAAAA==.',
Ch='Chewdawgg:BAAANQAECgYIBgAAAA==.Chewdogg:BAAANQAECggIEAAAAA==.Cheww:BAABNQAECn8pAAMSAAoKsBavWQAVAgASAAkK/RavWQAVAgAKAAIKaAx4dQA7AAAAAA==.Chicharrones:BAAANQADCgEIAQABNQAECgoKQAAOAOMgAA==.Chicknburger:BAAANQAECgEIAQAAAA==.Chlorofõrm:BAABNQAECn8bAAIUAAcKAgvWeQDhAAAUAAcKAgvWeQDhAAAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Choopamelo:BAAANQADCgEIAQAAAA==.Chopahoe:BAABNQAECn8tAAIWAAoKPR5zEgDIAgAWAAoKPR5zEgDIAgAAAA==.Chudlock:BAAANQADCggIEQABNQAECgoKUQASALAkAA==.Chumpcooker:BAAANQADCgYICAAAAA==.',
Cl='Clamius:BAACNQAFFH8RAAMXAAYKeiMYBQDAAAATAAQK0Ba2NQDuAAAXAAMKbyQYBQDAAAA1AAQKf0EAAxcACgouJToCAN4CABMACgqxI9YiAFEDABcACQoVJDoCAN4CAAAA.Cliff:BAABNQAECn8tAAIYAAoK4CLgDQBSAwAYAAoK4CLgDQBSAwAAAA==.',
Co='Colby:BAAANQAECgQIBAAAAA==.Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAABNQAECn8pAAMYAAoKzSShBACkAwAYAAoKzSShBACkAwAZAAgKnBwXLwC/AgAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cortex:BAAANQADCgIIAgAAAA==.Cosmic:BAAANQADCgYIBgAAAA==.Cotopla:BAABNQAECn8XAAITAAcK0A9E9QChAQATAAcK0A9E9QChAQAAAA==.',
Cr='Crimsondream:BAABNQAECn8rAAQaAAcKMgx9hAAfAQAaAAcKMgx9hAAfAQAVAAEKAAAAfgAvAAAbAAIKMgRcKAAqAAAAAA==.',
Da='Daemea:BAAANQAECgQIBgAAAA==.Dagov:BAAANQAECgIIAgAAAA==.Damocles:BAAANQADCgEIAQAAAA==.Darkart:BAAANQADCgYICgAAAA==.Darkshivers:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.Darkswarm:BAAANQAECgIIAgAAAA==.',
De='Deathlentlez:BAABNQAECn8zAAIcAAoKlBpcCgDqAQAcAAoKlBpcCgDqAQAAAA==.Decaylentlez:BAAANQAECgEIAQABNQAECgoKMwAcAJQaAA==.Deepséeded:BAAANQADCgEIAQABNQAECgoKNAAYACUgAA==.Delphyne:BAABNQAECn8pAAILAAkKCwmXDABVAQALAAkKCwmXDABVAQAAAA==.Demonhunter:BAAANQAECgQICAAAAA==.Demonià:BAABNQAECn8bAAMXAAgKJwSILACYAAATAAgKpQMZugAIAQAXAAQK3gSILACYAAAAAA==.Dewhey:BAAANQAECgUIBQABNQAECgoKPwAFABoYAA==.',
Di='Diamondsword:BAABNQAECn8jAAIDAAoKsRMZJwBiAgADAAoKsRMZJwBiAgAAAA==.Dinkleberg:BAAANQADCgEIAQAAAA==.Disçiple:BAAANQAECgEIAQABNQAECgoKNAAYACUgAA==.',
Dj='Djazz:BAAANQAECgIIAQAAAA==.',
Dm='Dmajor:BAAANQAECgEIAQAAAA==.',
Dr='Drewsan:BAABNQAECn8eAAIdAAkKUg3kZwCPAQAdAAkKUg3kZwCPAQAAAA==.Drowsee:BAABNQAECn8ZAAIMAAgKtgxmCwARAQAMAAgKtgxmCwARAQAAAA==.',
Du='Dulcinea:BAAANQAECgUIDQAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
['Dú']='Dúncan:BAAANQADCggIFwAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAABNQAECn85AAMOAAoK7hwFEwBdAgAOAAoKJRsFEwBdAgAPAAcKZh11CwAYAgAAAA==.',
Ei='Eirinny:BAAANQADCggIGAAAAA==.',
El='Eldes:BAAANQADCgEIAQAAAA==.Elindez:BAABNQAECn8YAAIUAAoKggxXWgBNAQAUAAoKggxXWgBNAQAAAA==.Elyviel:BAAANQAECgcICgAAAA==.',
En='Encantado:BAAANQAECgEIAQAAAA==.End:BAAANQADCggICAAAAA==.Endlesswaltz:BAAANQADCgcIBwAAAA==.',
Eo='Eowen:BAABNQAECn8rAAIDAAoKWA6BSAC/AQADAAoKWA6BSAC/AQAAAA==.',
Ep='Epitaph:BAAANQADCgYICwAAAA==.',
Ez='Ezmee:BAAANQAECgEIAQAAAA==.',
Fa='Faelicia:BAAANQADCgYIFwAAAA==.Falandoria:BAAANQAECgIIAgAAAA==.Fastnfurious:BAAANQAECgUIBgABNQAECgoKPwAFABoYAA==.',
Fe='Feorian:BAAANQADCgEIAQAAAA==.',
Fr='Freyâ:BAAANQAECgMIAwABNQAECgoKIgAEAMcTAA==.Frostdruid:BAAANQADCgEIAQAAAA==.Frowmae:BAAANQAECgUIBwAAAA==.',
Fu='Fundip:BAABNQAECn8XAAITAAcKaA2woQA1AQATAAcKaA2woQA1AQAAAA==.',
Fy='Fythra:BAAANQAECgIICgAAAA==.Fythri:BAAANQAECgIIBAABNQAECgIICgABAAAAAA==.',
['Fù']='Fùrìeüx:BAAANQAECgEIAQAAAA==.',
Ga='Gawdsmackk:BAAANQAECgQIBAABNQAECgQICwABAAAAAA==.',
Ge='Geolock:BAAANQAECgQICAAAAA==.Geoshaman:BAAANQADCgYIBwAAAA==.',
Gi='Gibbii:BAAANQAECgcIEQABNQAECgoKOQAbABQZAA==.Gibdergen:BAAANQAECgYIBgABNQAECgoKOQAbABQZAA==.Gibhasarms:BAAANQADCgYIBgABNQAECgoKOQAbABQZAA==.Giblock:BAABNQAECn85AAMbAAoKFBnZAwCvAgAbAAoKFBnZAwCvAgAVAAEKUwkENQApAAAAAA==.Ginju:BAABNQAECn8fAAIZAAgK5RpCRABlAgAZAAgK5RpCRABlAgAAAA==.',
Gl='Glamour:BAAANQADCggIFAABNQAECgcIFwATAGgNAA==.',
Go='Golomojek:BAAANQADCgYICgAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAABNQAECn85AAIeAAoKnSSIAQBDAwAeAAoKnSSIAQBDAwAAAA==.Grawfern:BAABNQAECn8vAAMfAAoKlSO4BwAHAwAfAAoKlSO4BwAHAwAHAAYK5QiSawAdAQAAAA==.Graziella:BAAANQADCgYICQABNQAECgYIDAABAAAAAA==.',
Gu='Guldave:BAAANQAECgMIAwAAAA==.Guthrie:BAAANQAECgYIDwAAAA==.',
Gw='Gwÿñ:BAAANQADCgQIBAAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAABNQAECn8vAAIYAAoKGBjSMwAcAgAYAAoKGBjSMwAcAgAAAA==.Harden:BAAANQADCgEIAQAAAA==.Hawktwua:BAAANQAECgEIAQABNQAECgcIFAAIAMkbAA==.',
He='Healforbeer:BAAANQAECgUIBQAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAABNQAECn8nAAIKAAgKCxyFFwCbAgAKAAgKCxyFFwCbAgAAAA==.Hext:BAAANQADCgQIBAABNQAECgoKOwADAOsTAA==.',
Ho='Holygral:BAAANQADCgEIAQABNQAECgoKOQAeAJ0kAA==.Holymun:BAAANQAECgYICwAAAA==.Holyox:BAABNQAECn85AAIJAAoKvgZ41wBtAQAJAAoKvgZ41wBtAQAAAA==.Hotcheeto:BAAANQAECgYICQAAAA==.Hotdog:BAAANQADCgIIAgAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.Hturtledk:BAAANQAECggIDwAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.',
['Hü']='Hüntress:BAABNQAECn8XAAIgAAkKOweVpwAeAQAgAAkKOweVpwAeAQAAAA==.',
Ig='Ignuskore:BAAANQAECgEIAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECgkJFAARAEUeAA==.Imgibby:BAABNQAECn8cAAISAAgKGRAgWQCeAQASAAgKGRAgWQCeAQABNQAECgoKOQAbABQZAA==.',
In='Inexorable:BAACNQAFFH8JAAIJAAIKOx3YIACeAAAJAAIKOx3YIACeAAA1AAQKfzAAAgkACQrRJNYYAOUCAAkACQrRJNYYAOUCAAAA.Inssaane:BAAANQADCggIDgAAAA==.Interesting:BAAANQADCgYIBgAAAA==.',
Io='Iolegnaro:BAABNQAECn8WAAITAAcKMyS+cgCYAgATAAcKMyS+cgCYAgABNQAFFAcIFAAZAOsiAA==.',
Ir='Irakwa:BAAANQAECgEIAQAAAA==.Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAACNQAFFH8cAAIWAAcK4CDcAgBNAgAWAAcK4CDcAgBNAgA1AAQKfzgAAhYACgq6JecDAJcDABYACgq6JecDAJcDAAAA.',
Iz='Izry:BAABNQAECn8fAAQFAAoKQRUSLAB8AQAEAAkKORAqOwDiAQAFAAYK/RUSLAB8AQAhAAQKjQ0YoQC5AAAAAA==.Izánámi:BAAANQADCggICAABNQAECggIGwAUAAILAA==.',
Ja='Jaason:BAABNQAECn8yAAMEAAkK5xqRKABUAgAEAAkKnhmRKABUAgAFAAcK/hMJbwA5AQAAAA==.Jalen:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQAECgUIDAABNQAECgcIFAAIAMkbAA==.',
Jh='Jhora:BAABNQAECn8UAAIZAAoK6hTPJwAPAgAZAAoK6hTPJwAPAgAAAA==.Jhunts:BAAANQAECgYICwAAAA==.',
Ji='Jinfizz:BAAANQAECgIIAgAAAA==.Jinfuse:BAABNQAECn8qAAMTAAoKWRnkZgC4AQATAAoKdhjkZgC4AQAXAAEKDBw9OwBSAAAAAA==.',
Jo='Jormungandr:BAAANQADCgIIAgAAAA==.',
Jp='Jpdh:BAABNQAECn9AAAQOAAoKNiP4EAAYAwAOAAoKOh74EAAYAwAPAAgK3iKmBgD2AQACAAoKqRlaFgDUAQAAAA==.Jpdumb:BAAANQAECgUIBQABNQAECgoKQAAOADYjAA==.',
Ju='Juddory:BAABNQAECn8XAAITAAYKQA362QDMAAATAAYKQA362QDMAAAAAA==.Junksvil:BAABNQAECn8UAAIIAAcKyRslHgD4AQAIAAcKyRslHgD4AQAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Ka='Kalystia:BAAANQADCgEIAQAAAA==.',
Ke='Kealthara:BAAANQAECgQIBQAAAA==.',
Kh='Khalyon:BAABNQAECn80AAITAAoK8BmKbQCjAgATAAoK8BmKbQCjAgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.Kilowatts:BAAANQAECgEIAgAAAA==.',
Ko='Koa:BAAANQAECgEIAQAAAA==.Koppel:BAABNQAECn8WAAIRAAcKiQknLwDBAAARAAcKiQknLwDBAAABNQAECgoKIAAgAKgSAA==.Korinth:BAECNQAFFH8NAAIJAAYKBQmwDwDiAAAJAAYKBQmwDwDiAAA1AAQKfzEAAwkACgqqGylRAKICAAkACgqqGylRAKICAAgAAgpnH4tWAIcAAAAA.',
Kr='Kriaalis:BAAANQAECggICgAAAA==.Krîm:BAAANQADCgEIAQAAAA==.',
Ku='Kunitsu:BAAANQAECgQICwAAAA==.',
Ky='Kyra:BAAANQAECgYIDQAAAA==.Kyril:BAABNQAECn8qAAIJAAkK3yPEGQBdAwAJAAkK3yPEGQBdAwAAAA==.',
['Kæ']='Kælas:BAAANQADCgUIBQAAAA==.',
La='Lagabriela:BAABNQAECn8uAAIFAAkK7QvlPAAkAQAFAAkK7QvlPAAkAQAAAA==.Lazuli:BAAANQADCgQIBAABNQAECgoKQAAOAOMgAA==.',
Le='Legault:BAABNQAECn8tAAIiAAkKyhVAAwCPAQAiAAkKyhVAAwCPAQAAAA==.Legionofboom:BAAANQAECgEIAwAAAA==.Lemanruss:BAAANQADCgQIBQAAAA==.Lethfel:BAAANQAECgcIEgAAAA==.',
Li='Lilgoukii:BAAANQAECgEIAgAAAA==.Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQAECgIIAgAAAA==.Lionfury:BAAANQAECgQICQABNQAFFAQICQAJABMGAA==.Lionguard:BAACNQAFFH8JAAIJAAQKEwbbGgCVAAAJAAQKEwbbGgCVAAA1AAQKfyQAAgkACgrwFMWGABoCAAkACgrwFMWGABoCAAAA.Livie:BAABNQAECn8XAAIJAAgKCA8lmABcAQAJAAgKCA8lmABcAQAAAA==.Lizzard:BAAANQAECgcIBwABNQAFFAQIBgAgANEUAA==.',
Lo='Loca:BAABNQAECn8uAAIYAAoK1we8ZwBLAQAYAAoK1we8ZwBLAQAAAA==.Lonelylad:BAAANQADCgEIAQAAAA==.Loops:BAAANQAECgEIAQAAAA==.Lorad:BAAANQADCgEIAQAAAA==.Loraddesmos:BAABNQAECn84AAMVAAoKmA+3AwC6AQAVAAoKmA+3AwC6AQAaAAIKcwUSBgEwAAAAAA==.Loáth:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.Lullaby:BAAANQAECgUIBQAAAA==.',
Ly='Lycanthrope:BAAANQAECgEIAwAAAA==.Lyship:BAAANQAECgQIBgAAAA==.',
Ma='Maeg:BAAANQAECgYICgABNQAECgkJFAARAEUeAA==.Mahll:BAABNQAECn8wAAIaAAoKoh7LGACXAgAaAAoKoh7LGACXAgAAAA==.Maidenchina:BAAANQAECgMIAwAAAA==.Maleveck:BAAANQAECgYIBgAAAA==.Marcato:BAAANQADCgQIBQABNQAECgYIDAABAAAAAA==.Marcdofu:BAAANQAECgEIAwAAAA==.Mardista:BAAANQADCgYIBgAAAA==.Mataquay:BAAANQAECgEIAgAAAA==.',
Mc='Mctanker:BAAANQAECggIEQAAAA==.',
Me='Meascii:BAABNQAECn88AAMSAAoKdR/OCwBkAwASAAoKdR/OCwBkAwAjAAgKvg7iCQCxAQAAAA==.Megavolt:BAAANQADCggICAABNQAFFAcIHAAWAOAgAA==.Megs:BAAANQADCggJEwAAAA==.Memebeams:BAAANQAECgQIBwAAAA==.Merc:BAACNQAFFH8LAAIWAAYKmwogCwAGAQAWAAYKmwogCwAGAQA1AAQKfzQAAhYACgpAIB8PAPECABYACgpAIB8PAPECAAAA.',
Mi='Miluo:BAAANQAECgMIBQABNQAECgkJJgAgAMMiAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBAAAAA==.Miredagger:BAAANQADCgEIAQABNQAFFAYIEQAeAEQYAA==.Mirefighter:BAAANQAECgMIAwABNQAFFAYIEQAeAEQYAA==.Mirespike:BAACNQAFFH8RAAMeAAYKRBivAQBWAQAeAAYKRBivAQBWAQAHAAEKxQKOHwA3AAA1AAQKfzUAAx4ACgroIpwEAK8CAB4ACgroIpwEAK8CAAcAAgqzGN1xAEgAAAAA.Mishiko:BAAANQAECgEIAQAAAA==.Mistbrew:BAAANQAECgYICwABNQAECgoKFwAQAGQVAA==.Miushi:BAEANQAECgEIAQABNQAFFAYIDQAJAAUJAA==.',
Mj='Mjoinir:BAAANQAECgMIAwAAAA==.',
Mo='Modin:BAAANQAECgYIEwABNQAECggIJQADAC4UAA==.Mommacougar:BAAANQADCgIIAgAAAA==.Moon:BAAANQADCgUIDQABNQADCgcIGwABAAAAAA==.Morawynd:BAAANQAECgQIDgAAAA==.Morlis:BAAANQAECgIIBQAAAA==.Morlock:BAABNQAECn8sAAIaAAoKAgpzlgCuAQAaAAoKAgpzlgCuAQAAAA==.Morningstahr:BAABNQAECn8iAAITAAoKMxjxigBpAgATAAoKMxjxigBpAgAAAA==.Morphìc:BAAANQAECgUIBgAAAA==.',
Mu='Munion:BAAANQAECgQJBAABNQAECgYICwABAAAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Mô']='Môrningstar:BAAANQADCgUIBQAAAA==.',
Na='Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQAECgQIBwAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyfused:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyvoked:BAAANQAECgUIBAABNQAECgUIDAABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEIAwAAAA==.',
Ni='Nickayla:BAABNQAECn8aAAIVAAYKoQdpFQCVAAAVAAYKoQdpFQCVAAAAAA==.Nikkaya:BAAANQADCgYJBgABNQAECggIFwAfACoWAA==.Nimblecow:BAAANQADCgMIBQAAAA==.',
No='Noobacleese:BAABNQAECn8uAAIJAAoKHRk5jAANAgAJAAoKHRk5jAANAgAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.Novarak:BAAANQADCgMIAwAAAA==.Noyn:BAAANQAECgEIAQABNQAECgkJJgAgAMMiAA==.',
Ny='Nyghtrider:BAAANQAECgUIEAAAAA==.Nymëra:BAABNQAECn8XAAIYAAgKgwwrmABKAQAYAAgKgwwrmABKAQAAAA==.Nyneeve:BAABNQAECn8iAAIKAAgK3AvvIQA7AQAKAAgK3AvvIQA7AQAAAA==.',
Od='Odinshunter:BAAANQAECgEIAQAAAA==.Odst:BAAANQAECgIIAgABNQAECgoKIgAEAMcTAA==.',
Ol='Olgrin:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.',
On='Onepunch:BAAANQADCgcIBwAAAA==.Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQAECgEIAgAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBQAAAA==.Pandaloons:BAAANQAECgEIAgAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICQAAAA==.Partita:BAAANQAECgYIDAAAAA==.',
Pb='Pbób:BAAANQAECggIEwAAAA==.',
Pe='Percocetpete:BAABNQAECn8rAAMSAAoKKyTgEgA0AwASAAoKKyTgEgA0AwAKAAgKRgcKNQB7AQAAAA==.Peregrine:BAAANQAECgEIAgAAAA==.',
Ph='Phaet:BAACNQAFFH8PAAMaAAYK5BPfEgDkAAAaAAUKIhTfEgDkAAAVAAEKJxM1DgBOAAA1AAQKfzMAAxoACgpuIVk4AKsCABoACQrLIVk4AKsCABUABAoHFRgyAP0AAAAA.Phaux:BAAANQAECgEIAwAAAA==.',
Pi='Piper:BAABNQAECn8aAAMSAAkKWwdtbgBUAQASAAkKWwdtbgBUAQAKAAUK7gNlWQCjAAAAAA==.',
Pl='Plâgue:BAABNQAECn8/AAMhAAoK1CAtCgCyAgAhAAoK1CAtCgCyAgAEAAUKYxAPWgDxAAAAAA==.',
Pr='Prot:BAAANQADCgUIBQAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgoKOgAeAOomAA==.Puntthegnome:BAAANQADCgEIAQABNQAFFAcIGQATAEQSAA==.',
Qu='Quackas:BAAANQADCgYIBgAAAA==.',
Ra='Rainforest:BAABNQAECn8XAAMfAAgKKhbWJABvAQAfAAcKehfWJABvAQAeAAIKnw8RPQAxAAAAAA==.Raktox:BAAANQADCggICgAAAA==.Ramden:BAABNQAECn81AAIJAAoKhweE1wBsAQAJAAoKhweE1wBsAQAAAA==.Rampant:BAABNQAECn8iAAQEAAoKxxPiKwDFAQAEAAoKxxPiKwDFAQAFAAMKKQxVqACBAAAhAAIKBBNevgBuAAAAAA==.Rampscii:BAAANQAECgcIEwABNQAECgoKIgAEAMcTAA==.Randalthorr:BAAANQADCgUIBQAAAA==.Randolier:BAABNQAECn8tAAMgAAoKZCACKgDwAgAgAAoKZCACKgDwAgAkAAEK5ANEagAkAAAAAA==.Ratherton:BAACNQAFFH8ZAAMTAAcKRBIVEAD2AQATAAYKIhYVEAD2AQAXAAEKywLkDwBOAAA1AAQKf0sAAxMACgoOIxsUAOUCABMACgr4IhsUAOUCABcAAQr0I8goAGkAAAAA.Rathtard:BAABNQAECn8rAAIgAAoK3xwSLQBfAgAgAAoK3xwSLQBfAgABNQAFFAcIGQATAEQSAA==.Rauzer:BAAANQADCgEIAQAAAA==.Razz:BAAANQAECgEIAQAAAA==.',
Re='Renuwu:BAABNQAECn9UAAISAAoKuhGlPwADAgASAAoKuhGlPwADAgAAAA==.Resoluteone:BAABNQAECn8+AAIFAAoKbAhsOAA5AQAFAAoKbAhsOAA5AQAAAA==.Retnu:BAAANQADCgQIDAAAAA==.Retrograde:BAAANQAECggICAAAAA==.Revelations:BAAANQAECgMIAwABNQAECgoKKQAYAM0kAA==.Revytwohand:BAACNQAFFH8RAAIWAAYKjBPNBgDtAAAWAAYKjBPNBgDtAAA1AAQKfzMAAhYACgrPH08RANYCABYACgrPH08RANYCAAAA.',
Rh='Rhok:BAAANQAECgUICQAAAA==.',
Ro='Robonome:BAAANQAECgEIAQAAAA==.Rootytooty:BAAANQADCgEIAQAAAA==.',
Ru='Rumii:BAAANQAECgQIBwAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
['Rö']='Rödrïck:BAAANQAECgYICwABNQAECgoKRQAaADsdAA==.',
Sa='Sabeladys:BAABNQAECn8bAAIJAAoKqwx0rwAxAQAJAAoKqwx0rwAxAQAAAA==.Saifir:BAABNQAECn8tAAMZAAgKHxcIvwAUAQAZAAUK3hAIvwAUAQAYAAgKmgvYfAAKAQAAAA==.Sallyd:BAAANQAECgEIAQAAAA==.Santorini:BAAANQADCgEIAgAAAA==.Sardmagia:BAAANQAECgIIAgABNQAECgUJDAABAAAAAA==.Sardmongo:BAAANQAECgEIAQAAAA==.Sarduccini:BAAANQAECgUJDAAAAA==.',
Se='Sekio:BAAANQADCgEIAQAAAA==.Sersi:BAAANQADCgQIBAAAAA==.',
Sh='Shadowpriest:BAAANQAECgEIAgAAAA==.Shamwowzer:BAAANQADCgQIBAAAAA==.Shelisaria:BAAANQAECgUICgAAAA==.Shiftken:BAAANQADCgMIAwAAAA==.Shingmar:BAAANQADCgEIAgAAAA==.Shoktherapy:BAABNQAECn80AAMYAAoKJSBVBgCYAwAYAAoKJSBVBgCYAwAZAAEKAAAHOAEyAAAAAA==.',
Si='Silvalus:BAAANQAECgMIBAAAAA==.Silvertide:BAABNQAECn87AAMZAAoKvBMMKwD8AQAZAAoKvBMMKwD8AQAYAAgKaw6IiwBtAQAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skonka:BAAANQADCggICAAAAA==.Skyeforce:BAAANQADCggIEAAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
Sm='Smargaid:BAAANQAECgEIAQAAAA==.Smellydeath:BAAANQADCgEIAQAAAA==.',
So='Soi:BAABNQAECn8mAAMgAAkKwyIqLwDfAgAgAAkKwyIqLwDfAgAkAAIKJA0BdABpAAAAAA==.Solas:BAAANQAECgUIDAAAAA==.Solvent:BAAANQADCggICwAAAA==.Sondaar:BAAANQADCgEIAQAAAA==.Sonoforak:BAAANQAECgMJAwAAAA==.',
Sp='Sped:BAABNQAECn8xAAIcAAoKKSADBgALAwAcAAoKKSADBgALAwAAAA==.',
Sr='Srouku:BAAANQADCgEIAQAAAA==.',
St='Staraleena:BAAANQAECgUIBQAAAA==.Stiffyhaze:BAAANQAECgQIBAAAAA==.Stillwët:BAAANQABCggICwAAAA==.Stingyr:BAABNQAECn8dAAIgAAcKBgl5pQAiAQAgAAcKBgl5pQAiAQABNQAECggIHgAgACMOAA==.Stormslight:BAAANQAECgYICwAAAA==.Stormsteel:BAAANQAECgMIBgAAAA==.Stossel:BAABNQAECn8gAAIgAAoKqBKIRQAMAgAgAAoKqBKIRQAMAgAAAA==.Stôrmrägé:BAAANQAECgMIBAAAAA==.',
Su='Subconscious:BAAANQAECgEIAwAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Sy='Sylvänäs:BAAANQAECgIIAwAAAA==.Synthrax:BAAANQADCgEIAQAAAA==.',
Ta='Tab:BAAANQAECgIIAQAAAA==.Tabio:BAAANQADCgYIBwAAAA==.Taboptics:BAAANQAECgQIBQAAAA==.Talas:BAABNQAECn8tAAIIAAoKRRjNGwAPAgAIAAoKRRjNGwAPAgAAAA==.Tamarack:BAAANQAECgUICQAAAA==.Tanksabunch:BAABNQAECn8eAAIdAAoKFhaRZwCQAQAdAAoKFhaRZwCQAQABNQAFFAgIHQAkAMchAA==.',
Te='Tegoz:BAAANQAECggICgAAAA==.Tehmay:BAAANQADCgIIAgAAAA==.Temocratus:BAAANQADCgEIAQABNQAECgMIBAABAAAAAA==.Tenssid:BAAANQADCggIGAAAAA==.Terrormisu:BAAANQAECgcICQAAAA==.',
Th='Thorclap:BAAANQAECgEJAQAAAA==.Thundertaker:BAAANQADCgYICgAAAA==.',
Ti='Tim:BAAANQADCggICgABNQAECgoKMAAQALcdAA==.Tiniashio:BAAANQAECgQIBAABNQAECggIKwAaADIMAA==.',
To='Tooru:BAACNQAFFH8GAAMgAAQK0RRDEgDeAAAgAAMK0RRDEgDeAAAkAAEKAADkHgAAAAA1AAQKf0QAAyAACgpqJVUIADYDACAACgpqJVUIADYDACQACAqoD341AKIBAAAA.Toquesitos:BAAANQADCgEIAQAAAA==.Toru:BAAANQADCgEIAQAAAA==.',
Tr='Traest:BAAANQAECgEIAwAAAA==.Traevok:BAAANQAECgEIAQAAAA==.Treebeef:BAAANQAECgMIAwAAAA==.Triena:BAAANQADCggJCAAAAA==.Trimas:BAAANQAECgEIAQAAAA==.',
Tt='Tt:BAABNQAECn8WAAQEAAcK8CPNFQBvAgAEAAcK8CPNFQBvAgAhAAEKsxu4zABTAAAFAAEKZAAAAAAAAAAAAA==.',
Tw='Twinkles:BAABNQAECn8lAAMDAAgKLhQ/WwAHAgADAAgKLhQ/WwAHAgAJAAMK+AsMdQEuAAAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ty='Typicaldrood:BAAANQAECgMIAwAAAA==.Typicalmonk:BAAANQADCgQIBAAAAA==.',
Ul='Ulysius:BAABNQAECn8vAAIJAAoKFxLPcwCnAQAJAAoKFxLPcwCnAQAAAA==.',
Va='Valkisek:BAABNQAECn8fAAIXAAoKuhZnBwB6AgAXAAoKuhZnBwB6AgAAAA==.Vallarfax:BAABNQAECn8kAAIgAAkKdhlmUAB+AgAgAAkKdhlmUAB+AgAAAA==.Vandro:BAABNQAECn87AAIDAAoK6xMrPwDlAQADAAoK6xMrPwDlAQAAAA==.Varea:BAABNQAECn8UAAISAAcKphF8fAAoAQASAAcKphF8fAAoAQABNQAECgoKRQATABgaAA==.Vashdk:BAACNQAFFH8RAAIFAAYKJx3VCgATAQAFAAYKJx3VCgATAQA1AAQKfzEAAgUACgqzJIgIAHYDAAUACgqzJIgIAHYDAAAA.',
Ve='Velcyn:BAABNQAECn8ZAAMaAAoK+iEoHwAIAwAaAAoK+iEoHwAIAwAVAAEKNROEdQA4AAAAAA==.Veloranas:BAABNQAECn9FAAMTAAoKGBp9NQBOAgATAAoKDRp9NQBOAgAXAAMK3xGTKwCeAAAAAA==.Venjince:BAAANQADCgYIBgAAAA==.Venôm:BAAANQADCgQIBAAAAA==.Vespyr:BAABNQAECn8eAAIgAAgKIw5rfgB1AQAgAAgKIw5rfgB1AQAAAA==.Vewdoo:BAABNQAECn89AAIZAAoKuyP/DQB5AwAZAAoKuyP/DQB5AwAAAA==.Vexiara:BAAANQADCgcIEAABNQAECgcICgABAAAAAA==.',
Vi='Vizimir:BAABNQAECn8aAAIXAAYKBws7HADCAAAXAAYKBws7HADCAAAAAA==.',
Vy='Vynstabbin:BAAANQAECgUJCgABNQAECggIDgABAAAAAA==.',
Wa='Waiwai:BAAANQAECgcICAAAAA==.Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAABNQAECn8iAAIgAAoK9RWjMwBHAgAgAAoK9RWjMwBHAgABNQAECgoKIgAEAMcTAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wh='Whimsyrage:BAAANQADCgEIAQAAAA==.Whiskeybear:BAAANQADCgYICAAAAA==.',
Wi='Wickedsinner:BAAANQAECgEIAgAAAA==.Wigglesimps:BAAANQADCgQIBAABNQAECgcIFAAIAMkbAA==.Willowes:BAAANQAECgEIAQAAAA==.Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wivvy:BAABNQAECn8fAAILAAoKww1/CADKAQALAAoKww1/CADKAQAAAA==.Wizkerbizkit:BAABNQAECn8gAAMkAAgKdwgETQD9AAAkAAYKAQkETQD9AAAgAAIKYQcYFgFQAAAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wooshira:BAAANQAECgEIAQAAAA==.',
Wy='Wyrmheal:BAABNQAECn9GAAIKAAoKXiLAAwAwAwAKAAoKXiLAAwAwAwAAAA==.Wyvvie:BAABNQAECn8dAAIlAAkKHhTxFAAsAgAlAAkKHhTxFAAsAgAAAA==.',
Ya='Yamihime:BAABNQAECn80AAMOAAoKwBi0IQCOAgAOAAoKwBi0IQCOAgACAAEKAAA2bgAxAAAAAA==.Yatiri:BAAANQAECgcIDwAAAA==.',
Ye='Yellowkano:BAAANQADCgEIAQAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.Zambas:BAAANQAECgMIAwAAAA==.',
Ze='Zeaket:BAACNQAFFH8hAAImAAcK4B4ZAADSAQAmAAcK4B4ZAADSAQA1AAQKfzkAAiYACgo9JscAAJgDACYACgo9JscAAJgDAAAA.Zephyr:BAAANQAECgQICAABNQAECggIHgAgACMOAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQAECggICgABNQAECgkJJgAgAMMiAA==.',
Zi='Zinbad:BAAANQAECgEIAQAAAA==.',
Zo='Zorcan:BAABNQAECn8XAAIbAAgKVRleBwCsAQAbAAgKVRleBwCsAQAAAA==.',
Zu='Zugzugz:BAAANQAECggICQAAAA==.Zulfilith:BAAANQAECgIIBAAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Àr']='Àrrhythmia:BAAANQAECgQIBQABNQAECgoKNAAYACUgAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Än']='Äncïênt:BAAANQADCgcIBwAAAA==.',
['Ða']='Ðachee:BAABNQAECn83AAMSAAkKsiFYGgDXAgASAAkKsiFYGgDXAgAjAAEKshSsEwA/AAAAAA==.',
['Ðo']='Ðora:BAAANQADCgMIAwAAAA==.',
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
