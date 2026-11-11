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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Paladin-Protection','Paladin-Retribution','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Mage-Arcane','Mage-Frost','Warlock-Destruction','DeathKnight-Unholy','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Warrior-Arms','Druid-Guardian','Druid-Feral','Hunter-BeastMastery','Rogue-Outlaw','Priest-Discipline','Hunter-Marksmanship','Hunter-Survival','Monk-Mistweaver',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aadrik:BAAANQADCggICAAAAA==.',
Ad='Adrenalin:BAAANQAECgYIEQAAAA==.Adversary:BAAANQADCgcICQAAAA==.',
Ae='Aennish:BAAANQABCgIIBgAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIEAAAAA==.',
Ai='Airibeth:BAAANQAECgMIAgAAAA==.Aiyanna:BAAANQAECgMIAwABNQAECgUIEAABAAAAAA==.',
Al='Alric:BAABNQAECn88AAICAAoKJRy5CwCLAgACAAoKJRy5CwCLAgAAAA==.Althalos:BAAANQADCgEIAQAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQAECgYIDgAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Ardhammer:BAAANQAECggIDQAAAA==.Arragorn:BAABNQAECn8nAAIDAAoKUQ8eUwC1AQADAAoKUQ8eUwC1AQAAAA==.',
As='Asendra:BAAANQAECgQICAAAAA==.Astal:BAACNQAFFH8SAAMEAAcK0RXmBQB3AQAEAAYK0RXmBQB3AQAFAAEKAABWLAAAAAA1AAQKfzUAAgQACgr+IqASAPkCAAQACgr+IqASAPkCAAAA.',
At='Ate:BAABNQAECn8kAAMGAAoKgxOCJwDkAQAGAAoKgxOCJwDkAQAHAAIKJQapeQBIAAAAAA==.',
Au='Aurathur:BAABNQAECn8iAAMIAAgKzhZOIQDZAQAIAAgKzhZOIQDZAQAJAAIKyAd4hgE2AAAAAA==.',
Av='Avyl:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.',
Ay='Ayannar:BAAANQADCgMIAwAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECggICgABAAAAAA==.Azriella:BAABNQAECn8bAAIKAAcKOwz5LAAHAQAKAAcKOwz5LAAHAQAAAA==.Azuren:BAABNQAECn8xAAQLAAoK8QzKDABxAQALAAoK8QzKDABxAQAMAAIKkgVrGgBAAAANAAEKngk+PAAkAAAAAA==.',
Ba='Bacon:BAABNQAECn9FAAMOAAoKOyHfGQDMAgAOAAoKOyHfGQDMAgAPAAEKlQgZMAAlAAAAAA==.Bamboozled:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.Bankai:BAABNQAECn8rAAIQAAkKnCO/BABFAwAQAAkKnCO/BABFAwAAAA==.',
Be='Beardedtroll:BAABNQAECn8VAAMRAAoKBhxJDQAaAwARAAkKRR5JDQAaAwASAAEKSgwozwA3AAAAAA==.Beefstrasz:BAACNQAFFH8SAAITAAcKtwSoDADAAQATAAcKtwSoDADAAQA1AAQKfzgAAhMACgqnFE9TACkCABMACgqnFE9TACkCAAAA.Beyla:BAABNQAECn8oAAIJAAoKIQ/3egDDAQAJAAoKIQ/3egDDAQAAAA==.',
Bh='Bhalecgos:BAAANQADCgYIEwAAAA==.',
Bi='Bishamon:BAAANQAECgIIBgAAAA==.',
Bl='Blank:BAAANQAECgMIAwAAAA==.Blazed:BAAANQAECgUICAAAAA==.Blazethorn:BAAANQAECgMIAwAAAA==.Bleau:BAAANQAECgYIDQAAAA==.Blethings:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.Bloodhornbob:BAAANQADCgUIDgAAAA==.Bloodimary:BAAANQADCgIIAgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodráyne:BAAANQADCgMIAwAAAA==.Bloodymary:BAABNQAECn8/AAIFAAoKGhj2GQAhAgAFAAoKGhj2GQAhAgAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAABNQAECn9CAAMUAAoKFBWmSwAdAgAUAAoKFBWmSwAdAgAVAAMKXxd0JwCQAAAAAA==.Bláze:BAAANQADCggICAABNQAECggIHgASAAILAA==.Blôodräge:BAAANQAECgYICQAAAA==.',
Bo='Boolzeye:BAAANQABCgQICAAAAA==.Bouncy:BAAANQAECgIIAgAAAA==.Bowl:BAACNQAFFH8SAAIIAAcKXxxaAgBzAQAIAAcKXxxaAgBzAQA1AAQKfzUAAggACgryIqIIABMDAAgACgryIqIIABMDAAAA.',
Br='Branchling:BAAANQAECgYICgABNQAFFAcIGQAUAEQSAA==.Breaklimit:BAAANQADCggIDQAAAA==.',
Bu='Burgi:BAAANQADCgIIAwABNQAECggIGwAWAFgOAA==.Butterkip:BAACNQAFFH8TAAIKAAYKKgzUBgAZAQAKAAYKKgzUBgAZAQA1AAQKfyYAAgoACgrBGx8YAJMCAAoACgrBGx8YAJMCAAAA.',
Ce='Cellan:BAAANQADCgYIEwAAAA==.',
Ch='Chewdawgg:BAAANQAECgYIBgAAAA==.Chewdogg:BAABNQAECn8XAAIXAAgKmAtFKwB4AQAXAAgKmAtFKwB4AQAAAA==.Cheww:BAABNQAECn8pAAMTAAoKsBavWQAVAgATAAkK/RavWQAVAgAKAAIKaAxgXQA2AAAAAA==.Chicharrones:BAAANQADCgEIAQABNQAECgoKRQAOADshAA==.Chicknburger:BAAANQAECgEIAQAAAA==.Chlorofõrm:BAABNQAECn8eAAISAAcKAgspMwAjAQASAAcKAgspMwAjAQAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Choopamelo:BAAANQADCgEIAQAAAA==.Chopahoe:BAABNQAECn8xAAIYAAoKOx9zEgDIAgAYAAoKOx9zEgDIAgAAAA==.Chudlock:BAAANQADCggIDwABNQAECgoKUQATALAkAA==.Chumpcooker:BAAANQADCgYICAAAAA==.',
Ci='Cinderic:BAAANQADCgMIAwAAAA==.',
Cl='Clamius:BAACNQAFFH8RAAMVAAYKeiMYBQDAAAAUAAQK0Ba2NQDuAAAVAAMKbyQYBQDAAAA1AAQKf0IAAxUACgqiJQ4BAD8DABQACgqxI9YiAFEDABUACgoMJA4BAD8DAAAA.Cliff:BAABNQAECn8xAAIZAAoKuSPgDQBSAwAZAAoKuSPgDQBSAwAAAA==.',
Co='Colby:BAAANQAECgQIBAAAAA==.Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAABNQAECn8pAAMZAAoKzSShBACkAwAZAAoKzSShBACkAwAaAAgKnBwXLwC/AgAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cortex:BAAANQADCgIIAgAAAA==.Cosmic:BAAANQADCgYIBgAAAA==.Cotopla:BAABNQAECn8XAAIUAAcK0A9E9QChAQAUAAcK0A9E9QChAQAAAA==.',
Cr='Crimsondream:BAABNQAECn8uAAQbAAcKMgwhlAAdAQAbAAcKMgwhlAAdAQAWAAEKAAAAfgAvAAAcAAIKMgTxLQAqAAAAAA==.',
Da='Daemea:BAAANQAECgQICgAAAA==.Dagov:BAAANQAECgIIAgAAAA==.Darkart:BAAANQADCgYICgAAAA==.Darkshivers:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.Darkswarm:BAAANQAECgIIAQAAAA==.',
De='Deathlentlez:BAABNQAECn80AAIdAAoKlBoODAB2AgAdAAoKlBoODAB2AgAAAA==.Decaylentlez:BAAANQAECgEIAQABNQAECgoKNAAdAJQaAA==.Deepséeded:BAAANQADCgEIAQABNQAECgoKQwAZADggAA==.Delphyne:BAABNQAECn8qAAILAAoKugiTDAB3AQALAAoKugiTDAB3AQAAAA==.Demonhunter:BAAANQAECgQICAAAAA==.Demonià:BAABNQAECn8eAAMUAAkKrwS1rAA4AQAUAAkKQAS1rAA4AQAVAAQK3gSILACYAAAAAA==.Dewhey:BAAANQAECgUIBQABNQAECgoKPwAFABoYAA==.',
Di='Diamondsword:BAABNQAECn8lAAIDAAoKsRP0LgBWAgADAAoKsRP0LgBWAgAAAA==.Dinkleberg:BAAANQABCgUIBgAAAA==.Disçiple:BAAANQAECgcICAABNQAECgoKQwAZADggAA==.',
Dj='Djazz:BAAANQAECgIIAQAAAA==.',
Dm='Dmajor:BAAANQADCgEIAQAAAA==.',
Dr='Drewsan:BAABNQAECn8gAAIeAAkKow6OcACbAQAeAAkKow6OcACbAQAAAA==.Drowsee:BAABNQAECn8cAAIMAAkKIAyoCgBFAQAMAAkKIAyoCgBFAQAAAA==.',
Du='Dulcinea:BAAANQAECgUIDQAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
['Dú']='Dúncan:BAAANQADCggIGQAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAABNQAECn9HAAMOAAoK2h20DwCiAgAOAAoK/By0DwCiAgAPAAcKZh11CwAYAgAAAA==.',
Ei='Eirinny:BAAANQADCggIFgAAAA==.',
El='Elindez:BAABNQAECn8YAAISAAoKggzJZgBXAQASAAoKggzJZgBXAQAAAA==.Elyviel:BAAANQAECggICgAAAA==.',
En='Encantado:BAAANQAECgEIAQAAAA==.End:BAAANQADCggICAAAAA==.Endlesswaltz:BAAANQADCgcIBwAAAA==.',
Eo='Eowen:BAABNQAECn8rAAIDAAoKWA5MVACxAQADAAoKWA5MVACxAQAAAA==.',
Ep='Epitaph:BAAANQADCgYICwAAAA==.',
Ez='Ezmee:BAAANQAECgEIAQAAAA==.',
Fa='Faelicia:BAAANQADCgYIFwAAAA==.Falandoria:BAAANQAECgMIAgAAAA==.Fastnfurious:BAAANQAECgUIBgABNQAECgoKPwAFABoYAA==.',
Fr='Freyâ:BAAANQAECgUIBQABNQAECgoKKgAEAKsXAA==.Frostdruid:BAAANQADCgEIAQAAAA==.Frowmae:BAAANQAECgUIBwAAAA==.',
Fu='Fundip:BAABNQAECn8XAAIUAAcKaA2AswAsAQAUAAcKaA2AswAsAQAAAA==.',
Fy='Fythra:BAAANQAECgQIDAABNQAECgUICAABAAAAAA==.Fythri:BAAANQAECgUICAAAAA==.',
['Fù']='Fùrìeüx:BAAANQAECgEIAQAAAA==.',
Ga='Gawdsmackk:BAAANQAECgQIBAABNQAECgQICwABAAAAAA==.',
Ge='Geolock:BAAANQAECgQIBwAAAA==.Geoshaman:BAAANQAECgEIAQAAAA==.',
Gi='Gibbii:BAABNQAECn8ZAAMfAAkKchYpEQAPAgAfAAkKchYpEQAPAgAHAAQKrgG2ewBDAAABNQAECgoKQgAcAFsbAA==.Gibdergen:BAAANQAECgYICAABNQAECgoKQgAcAFsbAA==.Gibhasarms:BAAANQADCgYIBgABNQAECgoKQgAcAFsbAA==.Giblock:BAABNQAECn9CAAMcAAoKWxsuAwB+AgAcAAoKWxsuAwB+AgAWAAEKUwlOOQApAAAAAA==.Ginju:BAABNQAECn8fAAIaAAgK5RpCRABlAgAaAAgK5RpCRABlAgAAAA==.',
Gl='Glamour:BAAANQADCggIGQABNQAECgcIFwAUAGgNAA==.',
Go='Golomojek:BAAANQADCgYICgAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAABNQAECn9CAAIgAAoKCyVbAQBaAwAgAAoKCyVbAQBaAwAAAA==.Grawfern:BAABNQAECn8vAAMfAAoKlSO4BwAHAwAfAAoKlSO4BwAHAwAHAAYK5QiSawAdAQAAAA==.Graziella:BAAANQADCgYICQABNQAECgYIDAABAAAAAA==.',
Gu='Guldave:BAAANQAECgMIAwAAAA==.Guthrie:BAAANQAECgYIDgAAAA==.',
Gw='Gwÿñ:BAAANQADCgQIBAAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAABNQAECn8vAAIZAAoKGBgARwBGAgAZAAoKGBgARwBGAgAAAA==.Harden:BAAANQADCgEIAQAAAA==.Hawktwua:BAAANQAECgEIAQABNQAECgcIFAAIAMkbAA==.',
He='Healforbeer:BAAANQAECgUIBQAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAABNQAECn8nAAIKAAgKCxyFFwCbAgAKAAgKCxyFFwCbAgAAAA==.Hext:BAAANQADCgQIBAABNQAECgoKQgADAGwUAA==.',
Ho='Holygral:BAAANQABCggIFAABNQAECgoKQgAgAAslAA==.Holymun:BAAANQAECgcICAAAAA==.Holyox:BAABNQAECn85AAIJAAoKvgZ41wBtAQAJAAoKvgZ41wBtAQAAAA==.Hotcheeto:BAAANQAECgYIBgAAAA==.Hotdog:BAAANQADCgQIBAAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.Hturtledk:BAAANQAECggIDAAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECggICgABAAAAAA==.',
['Hü']='Hüntress:BAABNQAECn8ZAAIhAAoK9QfVlwBoAQAhAAoK9QfVlwBoAQAAAA==.',
Ig='Ignuskore:BAAANQAECgEIAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECgoKFQARAAYcAA==.Imgibby:BAABNQAECn8cAAITAAgKGRDnaQCIAQATAAgKGRDnaQCIAQABNQAECgoKQgAcAFsbAA==.',
In='Inexorable:BAACNQAFFH8JAAIJAAIKOx3YIACeAAAJAAIKOx3YIACeAAA1AAQKfzEAAgkACQrRJJ8fANkCAAkACQrRJJ8fANkCAAAA.Inssaane:BAAANQADCggIDgAAAA==.Interesting:BAAANQADCgYIBgAAAA==.',
Io='Iolegnaro:BAABNQAECn8WAAIUAAcKMyS+cgCYAgAUAAcKMyS+cgCYAgABNQAFFAcIFAAaAOsiAA==.',
Ir='Irakwa:BAAANQAECgEIAQAAAA==.Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAACNQAFFH8dAAIYAAgKeR/cAgBNAgAYAAgKeR/cAgBNAgA1AAQKfzkAAhgACgo1JucDAJcDABgACgo1JucDAJcDAAAA.',
Iz='Izry:BAABNQAECn8fAAQFAAoKQRXaMQB2AQAEAAkKORAqOwDiAQAFAAYK/RXaMQB2AQAXAAQKjQ0YoQC5AAAAAA==.Izánámi:BAAANQADCggICAABNQAECggIHgASAAILAA==.',
Ja='Jaason:BAABNQAECn84AAMEAAkK5xqRKABUAgAEAAkKnhmRKABUAgAFAAgK+xOfMgBxAQAAAA==.Jalen:BAAANQADCgYIBgAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQAECgUICwABNQAECgcIFAAIAMkbAA==.',
Jh='Jhora:BAABNQAECn8YAAIaAAoKaBYNKQAqAgAaAAoKaBYNKQAqAgAAAA==.Jhunts:BAAANQAECgYICwAAAA==.',
Ji='Jinfizz:BAAANQAECgIIAgAAAA==.Jinfuse:BAABNQAECn8uAAMUAAoKWRl4kwBZAgAUAAoKdhh4kwBZAgAVAAEKDBw9OwBSAAAAAA==.',
Jo='Jormungandr:BAAANQADCgIIAgAAAA==.',
Jp='Jpdh:BAABNQAECn9FAAQOAAoKAST4EAAYAwAOAAoKOh74EAAYAwAPAAgK3iK/BwDwAQACAAoKGRvSFgDvAQAAAA==.Jpdumb:BAAANQAECgUIBQABNQAECgoKRQAOAAEkAA==.',
Ju='Juddory:BAABNQAECn8aAAIUAAYKQA1H3gDdAAAUAAYKQA1H3gDdAAAAAA==.Junksvil:BAABNQAECn8UAAIIAAcKyRslHgD4AQAIAAcKyRslHgD4AQAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Ka='Kalystia:BAAANQABCgIIAgAAAA==.',
Ke='Kealthara:BAAANQAECgQIBAAAAA==.',
Kh='Khalyon:BAABNQAECn80AAIUAAoK8BmKbQCjAgAUAAoK8BmKbQCjAgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.Kilowatts:BAAANQABCgEIAQAAAA==.',
Ko='Koa:BAAANQAECgEIAQAAAA==.Koppel:BAABNQAECn8dAAMRAAkKzQoHMgC+AAASAAUKlwkMlgDBAAARAAcKiQkHMgC+AAABNQAECgoKLwAhAN0WAA==.Korinth:BAECNQAFFH8OAAIJAAcKigk+CgAsAQAJAAcKigk+CgAsAQA1AAQKfzYAAwkACgqqGylRAKICAAkACgqqGylRAKICAAgAAwoiF4tWAIcAAAAA.',
Kr='Kriaalis:BAAANQAECggIDQAAAA==.',
Ku='Kunitsu:BAAANQAECgQICwAAAA==.',
Ky='Kyra:BAAANQAECgUIDwAAAA==.Kyril:BAABNQAECn8qAAIJAAkK3yPEGQBdAwAJAAkK3yPEGQBdAwAAAA==.',
['Kæ']='Kælas:BAAANQADCgUIBQAAAA==.',
La='Lagabriela:BAABNQAECn8uAAIFAAkK7QvUQwAgAQAFAAkK7QvUQwAgAQAAAA==.Lazuli:BAAANQADCgQIBQABNQAECgoKRQAOADshAA==.',
Le='Legault:BAABNQAECn82AAIiAAoKYhcXAgAfAgAiAAoKYhcXAgAfAgAAAA==.Legionofboom:BAAANQAECgEIAQAAAA==.Lemanruss:BAAANQADCgQIBAAAAA==.Lethfel:BAAANQAECgcIEgAAAA==.',
Li='Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQAECgIIAgAAAA==.Lionfury:BAAANQAECgQICQABNQAFFAQICwAJAGUGAA==.Lionguard:BAACNQAFFH8LAAIJAAQKZQaQGwCnAAAJAAQKZQaQGwCnAAA1AAQKfyUAAgkACgrwFMWGABoCAAkACgrwFMWGABoCAAAA.Livie:BAABNQAECn8XAAIJAAgKCA8jsQBYAQAJAAgKCA8jsQBYAQAAAA==.Lizzard:BAAANQAECgYIBgABNQAFFAQIBgAhANEUAA==.',
Lo='Loca:BAABNQAECn8zAAIZAAoK1wdMcwBDAQAZAAoK1wdMcwBDAQAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loraddesmos:BAABNQAECn89AAMWAAoKzxARBADJAQAWAAoKzxARBADJAQAbAAIKcwUYFQEuAAAAAA==.Loáth:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.Lullaby:BAAANQAECgUIBQAAAA==.',
Ly='Lyship:BAAANQAECgQIBgAAAA==.',
Ma='Maeg:BAAANQAECgYICgABNQAECgoKFQARAAYcAA==.Mahll:BAABNQAECn82AAIbAAoKmB/3FwCxAgAbAAoKmB/3FwCxAgAAAA==.Maidenchina:BAAANQAECgMIAwAAAA==.Maleveck:BAAANQAECgYIBgAAAA==.Marcato:BAAANQADCgQIBQABNQAECgYIDAABAAAAAA==.Marcdofu:BAAANQAECgUIBwAAAA==.Mardista:BAAANQADCgYIBgAAAA==.',
Mc='Mctanker:BAAANQAECgcIDwAAAA==.',
Me='Meascii:BAABNQAECn9DAAMTAAoKdR/OCwBkAwATAAoKdR/OCwBkAwAjAAgKvg7iCQCxAQAAAA==.Megavolt:BAAANQADCggICAABNQAFFAgIHQAYAHkfAA==.Megs:BAAANQADCggJEwAAAA==.Memebeams:BAAANQAECgQIBQAAAA==.Merc:BAACNQAFFH8LAAIYAAYKmwogCwAGAQAYAAYKmwogCwAGAQA1AAQKfzwAAhgACgorIXgIANYCABgACgorIXgIANYCAAAA.',
Mi='Miluo:BAAANQAECgMIBQABNQAECgkJJgAhAMMiAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBAAAAA==.Miredagger:BAAANQADCgEIAQABNQAFFAcIEgAgAP8WAA==.Mirefighter:BAAANQAECgMIAwABNQAFFAcIEgAgAP8WAA==.Mirespike:BAACNQAFFH8SAAMgAAcK/xbyAAAeAQAgAAcK/xbyAAAeAQAHAAEKxQLrIgA3AAA1AAQKfzYAAyAACgroIhAFADMDACAACgroIhAFADMDAAcAAgqzGGR6AEYAAAAA.Mistbrew:BAAANQAECgYICwABNQAECgoKFwAQAGQVAA==.Miushi:BAEANQABCgIIAgABNQAFFAcIDgAJAIoJAA==.',
Mj='Mjoinir:BAAANQAECgUIBgAAAA==.',
Mo='Modin:BAABNQAECn8XAAITAAcKaxG0aQCIAQATAAcKaxG0aQCIAQABNQAECggIJQADAC4UAA==.Mommacougar:BAAANQADCgIIAgAAAA==.Moon:BAAANQADCgUICgABNQADCgcIHAABAAAAAA==.Morawynd:BAAANQAECgQIEgAAAA==.Morlis:BAAANQAECgUICQAAAA==.Morlock:BAABNQAECn8vAAIbAAoKAgpzlgCuAQAbAAoKAgpzlgCuAQAAAA==.Morningstahr:BAABNQAECn8iAAIUAAoKMxjxigBpAgAUAAoKMxjxigBpAgAAAA==.Morphìc:BAAANQAECgUIBgAAAA==.',
Mu='Munion:BAAANQAECgQJBAABNQAECgcICAABAAAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Mô']='Môrningstar:BAAANQADCgUIBQAAAA==.',
Na='Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQAECgQIBAAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyfused:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyvoked:BAAANQAECgUIBAABNQAECgUIDAABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEIAgAAAA==.',
Ni='Nickayla:BAABNQAECn8aAAIWAAYKoQdxGACSAAAWAAYKoQdxGACSAAAAAA==.Nikkaya:BAAANQADCgYJBgABNQAECggIFwAfACoWAA==.Nimblecow:BAAANQADCgMIBQAAAA==.',
No='Noobacleese:BAABNQAECn8yAAIJAAoKFRo5jAANAgAJAAoKFRo5jAANAgAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.Novarak:BAAANQADCgMIAwAAAA==.Noyn:BAAANQAECgEIAQABNQAECgkJJgAhAMMiAA==.',
Ny='Nyghtrider:BAAANQAECgUIEAAAAA==.Nymëra:BAABNQAECn8XAAIZAAgKgwwrmABKAQAZAAgKgwwrmABKAQAAAA==.Nyneeve:BAABNQAECn8rAAIKAAoKTwzYGADDAQAKAAoKTwzYGADDAQAAAA==.',
Od='Odinshunter:BAAANQAECgEIAQAAAA==.Odst:BAAANQAECgIIBAABNQAECgoKKgAEAKsXAA==.',
Ol='Olgrin:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
On='Onepunch:BAAANQADCgcIBwAAAA==.Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQAECgEIAgAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBQAAAA==.Pandaloons:BAAANQABCgYICAABNQADCgYIBgABAAAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQAECgYIDAAAAA==.',
Pb='Pbób:BAAANQAECggIEAAAAA==.',
Pe='Percocetpete:BAABNQAECn8rAAMTAAoKKyTgEgA0AwATAAoKKyTgEgA0AwAKAAgKRgcKNQB7AQAAAA==.Peregrine:BAAANQAECgEIAQAAAA==.',
Ph='Phaet:BAACNQAFFH8QAAMbAAcKGBZ/DABBAQAbAAYK1RZ/DABBAQAWAAEKJxPcDwBNAAA1AAQKfzQAAxsACgpuIVk4AKsCABsACQrLIVk4AKsCABYABAoHFRgyAP0AAAAA.Phaux:BAAANQAECgEIAwAAAA==.',
Pi='Piper:BAABNQAECn8gAAMTAAkKnQhWdwBcAQATAAkKnQhWdwBcAQAKAAUK7gNlWQCjAAAAAA==.',
Pl='Plâgue:BAABNQAECn9HAAMXAAoK9CHzCQDNAgAXAAoK9CHzCQDNAgAEAAUKYxCLZADwAAAAAA==.',
Pr='Prot:BAAANQADCgUIBQAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgoKOwAgAOomAA==.Puntthegnome:BAAANQADCgEIAQABNQAFFAcIGQAUAEQSAA==.',
Qu='Quackas:BAAANQADCgYIBwAAAA==.',
Ra='Rainforest:BAABNQAECn8XAAMfAAgKKhbWJABvAQAfAAcKehfWJABvAQAgAAIKnw+6RQAxAAAAAA==.Raktox:BAAANQADCggICgAAAA==.Ramden:BAABNQAECn86AAIJAAoKgwiE1wBsAQAJAAoKgwiE1wBsAQAAAA==.Rampant:BAABNQAECn8qAAQEAAoKqxfcHwA7AgAEAAoKqxfcHwA7AgAFAAMKKQxVqACBAAAXAAIKBBNevgBuAAAAAA==.Rampscii:BAABNQAECn8bAAMTAAoKBR46LwByAgATAAoKBR46LwByAgAKAAQKPA3USAB0AAABNQAECgoKKgAEAKsXAA==.Randalthorr:BAAANQADCgUIBQAAAA==.Randolier:BAABNQAECn8xAAMhAAoKtSACKgDwAgAhAAoKtSACKgDwAgAkAAEK5ANBcQAkAAAAAA==.Ratherton:BAACNQAFFH8ZAAMUAAcKRBIVEAD2AQAUAAYKIhYVEAD2AQAVAAEKywKyEwBGAAA1AAQKf04AAxQACgp4IzIUAPICABQACgpiIzIUAPICABUAAQr0I6stAGgAAAAA.Rathtard:BAABNQAECn8rAAIhAAoK3xy/NQBhAgAhAAoK3xy/NQBhAgABNQAFFAcIGQAUAEQSAA==.Rauzer:BAAANQABCgIIAgAAAA==.Razz:BAAANQABCgIIAgAAAA==.',
Re='Renuwu:BAABNQAECn9VAAITAAoKXhLZSAD/AQATAAoKXhLZSAD/AQAAAA==.Resoluteone:BAABNQAECn9EAAIFAAoKbAjuPgA2AQAFAAoKbAjuPgA2AQAAAA==.Retnu:BAAANQADCgQIDAAAAA==.Retrograde:BAAANQAECggIEAAAAA==.Revelations:BAAANQAECgMIAwABNQAECgoKKQAZAM0kAA==.Revytwohand:BAACNQAFFH8SAAIYAAcKoBDSBQAyAQAYAAcKoBDSBQAyAQA1AAQKfzUAAhgACgrPH08RANYCABgACgrPH08RANYCAAAA.',
Rh='Rhok:BAAANQAECgQICwAAAA==.',
Ro='Robonome:BAAANQADCgUIBQAAAA==.Roker:BAAANQAECgIIAgABNQAECgoKLwAhAN0WAA==.',
Ru='Rumii:BAAANQAECgYICgAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
['Rö']='Rödrïck:BAAANQAECgYICgABNQAECgoKRQAbADsdAA==.',
Sa='Sabeladys:BAABNQAECn8fAAIJAAoKvgyRvgA/AQAJAAoKvgyRvgA/AQAAAA==.Saifir:BAABNQAECn8uAAMaAAgKHxcIvwAUAQAaAAUK3hAIvwAUAQAZAAgKmgvOiQACAQAAAA==.Sallyd:BAAANQAECgEIAQAAAA==.Sardmagia:BAAANQAECgIIAgABNQAECgUJDAABAAAAAA==.Sardmongo:BAAANQAECgEIAQAAAA==.Sarduccini:BAAANQAECgUJDAAAAA==.',
Se='Sersi:BAAANQADCgQIBAAAAA==.',
Sh='Shadowpriest:BAAANQABCgIIAgAAAA==.Shamwowzer:BAAANQADCgQIBQAAAA==.Shelisaria:BAAANQAECgcIDAAAAA==.Shiftken:BAAANQADCgMIAwAAAA==.Shingmar:BAAANQADCgEIAQAAAA==.Shoktherapy:BAABNQAECn9DAAMZAAoKOCDbBwCMAwAZAAoKOCDbBwCMAwAaAAEKAAAHOAEyAAAAAA==.',
Si='Silvalus:BAAANQAECgMIAwAAAA==.Silvertide:BAABNQAECn9CAAMaAAoKexS/LwAFAgAaAAoKexS/LwAFAgAZAAgKaw6IiwBtAQAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skonka:BAAANQADCggICAAAAA==.Skyeforce:BAAANQADCggIDwAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
Sm='Smargaid:BAAANQAECgEIAQAAAA==.',
So='Soi:BAABNQAECn8mAAMhAAkKwyIqLwDfAgAhAAkKwyIqLwDfAgAkAAIKJA0BdABpAAAAAA==.Solas:BAAANQAECgUICQAAAA==.Solvent:BAAANQADCggICwAAAA==.Sondaar:BAAANQABCgcIDwAAAA==.Sonoforak:BAAANQAECgMJAwAAAA==.',
Sp='Sped:BAABNQAECn8xAAIdAAoKKSADBgALAwAdAAoKKSADBgALAwAAAA==.',
St='Staraleena:BAAANQAECgUIBAAAAA==.Stiffyhaze:BAAANQAECgQIBAAAAA==.Stillwët:BAAANQABCggICwAAAA==.Stingyr:BAABNQAECn8kAAIhAAcKBgkiuQAkAQAhAAcKBgkiuQAkAQABNQAECggIJQAhANoOAA==.Stormslight:BAAANQAECgYIDgAAAA==.Stormsteel:BAAANQAECgIIAQAAAA==.Stossel:BAABNQAECn8vAAIhAAoK3RYkOABaAgAhAAoK3RYkOABaAgAAAA==.Stôrmrägé:BAAANQAECgMIAwAAAA==.',
Su='Subconscious:BAAANQAECgIIAwAAAA==.Sulfion:BAAANQADCgEIAQAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Ta='Tabio:BAAANQADCgYIBwAAAA==.Taboptics:BAAANQAECgUIBAAAAA==.Tabs:BAAANQADCgEIAQAAAA==.Talas:BAABNQAECn8xAAIIAAoKShnNGwAPAgAIAAoKShnNGwAPAgAAAA==.Tamarack:BAAANQAECgUICAAAAA==.Tanksabunch:BAABNQAECn8eAAIeAAoKFhY8dwCJAQAeAAoKFhY8dwCJAQABNQAFFAgIHQAkAMchAA==.',
Te='Tegoz:BAABNQAECn8UAAIgAAoKzxS8CwD6AQAgAAoKzxS8CwD6AQAAAA==.Tehmay:BAAANQADCgIIAgAAAA==.Temocratus:BAAANQADCgEIAgABNQAECgMIAwABAAAAAA==.Tenssid:BAAANQADCggIGAAAAA==.Terrormisu:BAAANQAECgcICQAAAA==.',
Th='Thorclap:BAAANQAECgEJAQAAAA==.Thundertaker:BAAANQADCgYICgAAAA==.',
Ti='Tim:BAAANQADCggICgABNQAECgoKMAAQALcdAA==.Tiniashio:BAAANQAECgQIBAABNQAECgcILgAbADIMAA==.',
To='Tooru:BAACNQAFFH8GAAMhAAQK0RQlFQDZAAAhAAMK0RQlFQDZAAAkAAEKAADyIgAAAAA1AAQKf0sABCEACgpqJTELACwDACEACgpqJTELACwDACQACAqoD341AKIBACUABgp4FcIHAHsBAAAA.',
Tr='Traest:BAAANQAECgEIAgAAAA==.Treebeef:BAAANQAECgMIAwAAAA==.Triena:BAAANQADCggJCAAAAA==.Trimas:BAAANQAECgEIAQAAAA==.',
Tt='Tt:BAABNQAECn8YAAQEAAcK8CMaGgBoAgAEAAcK8CMaGgBoAgAXAAEKsxu4zABTAAAFAAEKZAAAAAAAAAAAAA==.',
Tw='Twinkles:BAABNQAECn8lAAMDAAgKLhQ/WwAHAgADAAgKLhQ/WwAHAgAJAAMK+AvGdwE/AAAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ty='Typicaldrood:BAAANQAECgMIAwAAAA==.Typicalmonk:BAAANQADCgQIBAAAAA==.',
Ul='Ulysius:BAABNQAECn8zAAIJAAoKQhNxewDCAQAJAAoKQhNxewDCAQAAAA==.',
Va='Valkisek:BAABNQAECn8fAAIVAAoKuhZnBwB6AgAVAAoKuhZnBwB6AgAAAA==.Vallarfax:BAABNQAECn8kAAIhAAkKdhlmUAB+AgAhAAkKdhlmUAB+AgAAAA==.Vandro:BAABNQAECn9CAAMDAAoKbBSUSADeAQADAAoKbBSUSADeAQAIAAYKpgluNADPAAAAAA==.Varea:BAABNQAECn8UAAITAAcKphGsiQAjAQATAAcKphGsiQAjAQABNQAECgoKRgAUABgaAA==.Vashdk:BAACNQAFFH8SAAIFAAcKSB3lCABrAQAFAAcKSB3lCABrAQA1AAQKfzIAAgUACgqzJIgIAHYDAAUACgqzJIgIAHYDAAAA.',
Ve='Velcyn:BAABNQAECn8dAAMbAAoKISMoHwAIAwAbAAoKISMoHwAIAwAWAAEKNROEdQA4AAAAAA==.Veloranas:BAABNQAECn9GAAMUAAoKGBr3PQBGAgAUAAoKDRr3PQBGAgAVAAMK3xGTKwCeAAAAAA==.Venjince:BAAANQADCgYIBgAAAA==.Venôm:BAAANQADCgQIBAAAAA==.Vespyr:BAABNQAECn8lAAIhAAgK2g4xiQCJAQAhAAgK2g4xiQCJAQAAAA==.Vewdoo:BAABNQAECn9EAAIaAAoKySP/DQB5AwAaAAoKySP/DQB5AwAAAA==.Vexiara:BAAANQADCgcIDwABNQAECggICgABAAAAAA==.',
Vi='Vizimir:BAABNQAECn8aAAIVAAYKBwuiJgC9AAAVAAYKBwuiJgC9AAAAAA==.',
Vy='Vynstabbin:BAAANQAECgUJCgABNQAECggIDQABAAAAAA==.',
Wa='Waiwai:BAAANQAECgcICQAAAA==.Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAABNQAECn8qAAIhAAoK/hYXPQBMAgAhAAoK/hYXPQBMAgABNQAECgoKKgAEAKsXAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wh='Whiskeybear:BAAANQADCgYICAAAAA==.',
Wi='Wickedsinner:BAAANQAECgEIAQAAAA==.Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wivvy:BAABNQAECn8fAAILAAoKww2pCQDHAQALAAoKww2pCQDHAQAAAA==.Wizkerbizkit:BAABNQAECn8mAAMhAAgKaQmPmgBjAQAhAAYKPAmPmgBjAQAkAAYKAQkETQD9AAAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wooshira:BAAANQAECgEIAQAAAA==.',
Wy='Wyrmheal:BAABNQAECn9GAAIKAAoKXiKABAAqAwAKAAoKXiKABAAqAwAAAA==.Wyvvie:BAABNQAECn8kAAImAAkKGhj5DQApAgAmAAkKGhj5DQApAgAAAA==.',
Ya='Yamihime:BAABNQAECn86AAMOAAoK3xm0IQCOAgAOAAoK3xm0IQCOAgACAAIKvg+lUwA1AAAAAA==.Yatiri:BAAANQAECgcIDAAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.Zambas:BAAANQAECgMIAwAAAA==.',
Ze='Zeaket:BAACNQAFFH8jAAIlAAgKRB8QAAAvAgAlAAgKRB8QAAAvAgA1AAQKf0IAAiUACgqVJhMAAJsDACUACgqVJhMAAJsDAAAA.Zef:BAAANQAECgQIBAAAAA==.Zephyr:BAAANQAECgQICAABNQAECggIJQAhANoOAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQAECggICQABNQAECgkJJgAhAMMiAA==.',
Zo='Zorcan:BAABNQAECn8ZAAIcAAgKGRocCQCsAQAcAAgKGRocCQCsAQAAAA==.',
Zu='Zugzugz:BAAANQAECggICAAAAA==.Zulfilith:BAAANQAECgQICAAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Àr']='Àrrhythmia:BAAANQAECgcICgABNQAECgoKQwAZADggAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Än']='Äncïênt:BAAANQADCgcIBwAAAA==.',
['Ða']='Ðachee:BAABNQAECn85AAQTAAoKkiCVFwAJAwATAAoKkiCVFwAJAwAjAAEKshQHFgBAAAAKAAEKAADJcwAAAAAAAA==.',
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
