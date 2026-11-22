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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Paladin-Protection','Paladin-Retribution','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Mage-Arcane','Mage-Frost','Warlock-Destruction','Warrior-Protection','DeathKnight-Unholy','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Affliction','Warrior-Arms','Druid-Guardian','Druid-Feral','Hunter-BeastMastery','Rogue-Outlaw','Priest-Discipline','Hunter-Marksmanship','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aadrik:BAAANQADCggICAAAAA==.',
Ad='Adrenalin:BAAANQAECgYIEQAAAA==.Adversary:BAAANQADCgcICQAAAA==.',
Ae='Aennish:BAAANQABCgIIBgAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIEAAAAA==.',
Ai='Airibeth:BAAANQAECgMIAgAAAA==.Aiyanna:BAAANQAECgMIAwABNQAECgUIEAABAAAAAA==.',
Al='Alric:BAABNQAECn88AAICAAoKJRwkDQCBAgACAAoKJRwkDQCBAgAAAA==.Althalos:BAAANQABCgQIBgAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQAECgcIEgAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Ardhammer:BAAANQAECggIDQAAAA==.Arragorn:BAABNQAECn8nAAIDAAoKUQ+2ZADqAQADAAoKUQ+2ZADqAQAAAA==.',
As='Asendra:BAAANQAECgQICAAAAA==.Astal:BAACNQAFFH8SAAMEAAcK0RVgBwB0AQAEAAYK0RVgBwB0AQAFAAEKAACiLwAAAAA1AAQKfzcAAgQACgr+IqASAPkCAAQACgr+IqASAPkCAAAA.',
At='Ate:BAABNQAECn8kAAMGAAoKgxOCJwDkAQAGAAoKgxOCJwDkAQAHAAIKJQahfwBIAAAAAA==.',
Au='Aurathur:BAABNQAECn8jAAMIAAgKzhZOIQDZAQAIAAgKzhZOIQDZAQAJAAIKeQuyjgE7AAAAAA==.',
Av='Avyl:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.',
Ay='Ayannar:BAAANQADCgMIAwAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECggICgABAAAAAA==.Azriella:BAABNQAECn8bAAIKAAcKOwx0MAAHAQAKAAcKOwx0MAAHAQAAAA==.Azuren:BAABNQAECn8xAAQLAAoK8QytDQBwAQALAAoK8QytDQBwAQAMAAIKkgUNHABAAAANAAEKngnxPgAkAAAAAA==.',
Ba='Bacon:BAABNQAECn9FAAMOAAoKOyHfGQDMAgAOAAoKOyHfGQDMAgAPAAEKlQgJMwAlAAAAAA==.Bamboozled:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.Bankai:BAABNQAECn8rAAIQAAkKnCO/BABFAwAQAAkKnCO/BABFAwAAAA==.',
Be='Beardedtroll:BAABNQAECn8VAAMRAAoKBhxJDQAaAwARAAkKRR5JDQAaAwASAAEKSgzr2gA3AAAAAA==.Beefstrasz:BAACNQAFFH8SAAITAAcKtwQSDwC1AQATAAcKtwQSDwC1AQA1AAQKfz4AAxMACgoBFU9TACkCABMACgoBFU9TACkCAAoABAr6EEY+ALcAAAAA.Beyla:BAABNQAECn8oAAIJAAoKIQ/3hgC+AQAJAAoKIQ/3hgC+AQAAAA==.',
Bh='Bhalecgos:BAAANQADCgYIEwAAAA==.',
Bi='Bishamon:BAAANQAECgIIBgAAAA==.',
Bl='Blank:BAAANQAECgMIAwAAAA==.Blazed:BAAANQAECgUICAAAAA==.Blazethorn:BAAANQAECgMIBgAAAA==.Bleau:BAAANQAECgYIDQAAAA==.Blethings:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.Bloodhornbob:BAAANQADCgUIDgAAAA==.Bloodimary:BAAANQADCgIIAgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodráyne:BAAANQADCgMIAwAAAA==.Bloodymary:BAABNQAECn8/AAIFAAoKGhhqHAAaAgAFAAoKGhhqHAAaAgAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAABNQAECn9CAAMUAAoKFBWIUQAcAgAUAAoKFBWIUQAcAgAVAAMKXxeVKgCPAAAAAA==.Bláze:BAAANQADCggICAABNQAECggIJwASAC0LAA==.Blôodräge:BAAANQAECgYICQAAAA==.',
Bo='Boolzeye:BAAANQABCgQICAAAAA==.Bouncy:BAAANQAECgIIAgAAAA==.Bowl:BAACNQAFFH8SAAIIAAcKXxznAgBuAQAIAAcKXxznAgBuAQA1AAQKfzUAAggACgryIqIIABMDAAgACgryIqIIABMDAAAA.',
Br='Branchling:BAAANQAECgYICgABNQAFFAgIGwAUAFYRAA==.Breaklimit:BAAANQADCggIDQAAAA==.',
Bu='Burgi:BAAANQADCgIIAgABNQAECggIGwAWAFgOAA==.Butterkip:BAACNQAFFH8TAAIKAAYKKgz2BwAYAQAKAAYKKgz2BwAYAQA1AAQKfyYAAgoACgrBGx8YAJMCAAoACgrBGx8YAJMCAAAA.',
Ce='Cellan:BAAANQADCgYIEwAAAA==.',
Ch='Chaoslentlez:BAAANQAECgUIBgABNQAECgoKNAAXAJQaAA==.Chewdawgg:BAAANQAECgYIBgAAAA==.Chewdogg:BAABNQAECn8XAAIYAAgKmAt3LgB3AQAYAAgKmAt3LgB3AQAAAA==.Cheww:BAABNQAECn8rAAMTAAoKsBavWQAVAgATAAkK/RavWQAVAgAKAAIKFA3DYQA4AAAAAA==.Chicharrones:BAAANQADCgEIAQABNQAECgoKRQAOADshAA==.Chicknburger:BAAANQAECgEIAQAAAA==.Chlorofõrm:BAABNQAECn8nAAISAAcKLQspMwAjAQASAAcKLQspMwAjAQAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Choopamelo:BAAANQADCgEIAQAAAA==.Chopahoe:BAABNQAECn8xAAIZAAoKOx9zEgDIAgAZAAoKOx9zEgDIAgAAAA==.Chudlock:BAAANQADCggIDwABNQAECgoKUQATALAkAA==.Chumpcooker:BAAANQADCgYICAAAAA==.',
Ci='Cinderic:BAAANQADCgMIAwAAAA==.',
Cl='Clamius:BAACNQAFFH8RAAMVAAYKeiMYBQDAAAAUAAQK0Ba2NQDuAAAVAAMKbyQYBQDAAAA1AAQKf0IAAxUACgqiJVIBADoDABQACgqxI9YiAFEDABUACgoMJFIBADoDAAAA.Cliff:BAABNQAECn8xAAIaAAoKuSPgDQBSAwAaAAoKuSPgDQBSAwAAAA==.',
Co='Colby:BAAANQAECgQIBAAAAA==.Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAABNQAECn8pAAMaAAoKzSShBACkAwAaAAoKzSShBACkAwAbAAgKnBwXLwC/AgAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cortex:BAAANQADCgIIAgAAAA==.Cosmic:BAAANQADCgYIBgAAAA==.Cotopla:BAABNQAECn8XAAIUAAcK0A9E9QChAQAUAAcK0A9E9QChAQAAAA==.',
Cr='Crimsondream:BAABNQAECn8uAAQcAAcKMgzmnQAcAQAcAAcKMgzmnQAcAQAWAAEKAAAAfgAvAAAdAAIKMgSnMQApAAAAAA==.',
Da='Daemea:BAAANQAECgQICgAAAA==.Dagov:BAAANQAECgIIAgAAAA==.Darkart:BAAANQADCgYICgAAAA==.Darkshivers:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.Darkswarm:BAAANQAECgIIAQAAAA==.',
De='Deathlentlez:BAABNQAECn80AAIXAAoKlBoODAB2AgAXAAoKlBoODAB2AgAAAA==.Decaylentlez:BAAANQAECgEIAQABNQAECgoKNAAXAJQaAA==.Deepséeded:BAAANQADCgEIAQABNQAECgoKSwAaAEUhAA==.Delphyne:BAABNQAECn8qAAILAAoKughzDQB2AQALAAoKughzDQB2AQAAAA==.Demonhunter:BAAANQAECgQICAAAAA==.Demonià:BAABNQAECn8fAAMUAAkKrwR0tgA4AQAUAAkKQAR0tgA4AQAVAAQK3gSILACYAAAAAA==.Dewhey:BAAANQAECgUIBQABNQAECgoKPwAFABoYAA==.',
Di='Diamondsword:BAABNQAECn8lAAIDAAoKsRNqNQBHAgADAAoKsRNqNQBHAgAAAA==.Dinkleberg:BAAANQABCgUIBgAAAA==.Disçiple:BAAANQAECggIDQABNQAECgoKSwAaAEUhAA==.',
Dj='Djazz:BAAANQAECgEIAQAAAA==.',
Dr='Drewsan:BAABNQAECn8kAAIeAAkKPA/2dgCgAQAeAAkKPA/2dgCgAQAAAA==.Drowsee:BAABNQAECn8dAAIMAAkKpwxTCwBJAQAMAAkKpwxTCwBJAQAAAA==.',
Du='Dulcinea:BAAANQAECgUIDQAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
['Dú']='Dúncan:BAAANQADCggIFwAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAABNQAECn9PAAMOAAoKgCCcCwDlAgAOAAoKox+cCwDlAgAPAAcKZh11CwAYAgAAAA==.',
Ei='Eirinny:BAAANQADCggIFgAAAA==.',
El='Elindez:BAABNQAECn8YAAISAAoKggzTcABXAQASAAoKggzTcABXAQAAAA==.Elyviel:BAAANQAECggICgAAAA==.',
En='Encantado:BAAANQAECgEIAQAAAA==.End:BAAANQADCggICAAAAA==.Endlesswaltz:BAAANQADCgcIBwAAAA==.',
Eo='Eowen:BAABNQAECn8rAAIDAAoKWA4CXACoAQADAAoKWA4CXACoAQAAAA==.',
Ep='Epitaph:BAAANQADCgYIEQAAAA==.',
Ez='Ezmee:BAAANQAECgEIAQAAAA==.',
Fa='Faelicia:BAAANQADCgYIFwAAAA==.Falandoria:BAAANQAECgMIAgAAAA==.Fastnfurious:BAAANQAECgUIBgABNQAECgoKPwAFABoYAA==.',
Fr='Freyâ:BAAANQAECgUIBQABNQAECgoKMgAEAFoZAA==.Frostdruid:BAAANQADCgEIAQAAAA==.Frowmae:BAAANQAECgUIBwAAAA==.',
Fu='Fundip:BAABNQAECn8ZAAIUAAgKug19mQByAQAUAAgKug19mQByAQAAAA==.',
Fy='Fythra:BAAANQAECgQIEAAAAA==.Fythri:BAAANQAECgQICgABNQAECgQIEAABAAAAAA==.',
['Fù']='Fùrìeüx:BAAANQAECgEIAQAAAA==.',
Ga='Gawdsmackk:BAAANQAECgQIBAABNQAECgQICwABAAAAAA==.',
Ge='Geolock:BAAANQAECgQIBwAAAA==.Geoshaman:BAAANQAECgQIBQAAAA==.',
Gi='Gibbii:BAABNQAECn8ZAAMfAAkKchYcEwAJAgAfAAkKchYcEwAJAgAHAAQKrgG2gQBCAAABNQAECgoKQgAdAFsbAA==.Gibdergen:BAAANQAECgYICAABNQAECgoKQgAdAFsbAA==.Gibhasarms:BAAANQADCgYIBgABNQAECgoKQgAdAFsbAA==.Giblock:BAABNQAECn9CAAMdAAoKWxutAwB0AgAdAAoKWxutAwB0AgAWAAEKUwkoPAApAAAAAA==.Ginju:BAABNQAECn8fAAIbAAgK5RpCRABlAgAbAAgK5RpCRABlAgAAAA==.',
Gl='Glamour:BAAANQADCggIHgABNQAECggIGQAUALoNAA==.',
Go='Golomojek:BAAANQADCgYICgAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAACNQAFFH8GAAIgAAIKjB8xAgC8AAAgAAIKjB8xAgC8AAA1AAQKf0YAAiAACgpYJVABAGMDACAACgpYJVABAGMDAAAA.Grawfern:BAABNQAECn8vAAMfAAoKlSO4BwAHAwAfAAoKlSO4BwAHAwAHAAYK5QiSawAdAQAAAA==.Graziella:BAAANQADCgYICQABNQAECgYIDAABAAAAAA==.',
Gu='Guldave:BAAANQAECgMIAwAAAA==.Guthrie:BAAANQAECgcIDgAAAA==.',
Gw='Gwÿñ:BAAANQADCgQIBAAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAABNQAECn8yAAMaAAoKGBgARwBGAgAaAAoKGBgARwBGAgAbAAEKEQILFAEaAAAAAA==.Harden:BAAANQADCgEIAQAAAA==.Hawktwua:BAAANQAECggICQAAAA==.',
He='Healforbeer:BAAANQAECgUIBQAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAABNQAECn8nAAIKAAgKCxyFFwCbAgAKAAgKCxyFFwCbAgAAAA==.Hext:BAAANQADCgQIBAABNQAECgoKQgADAGwUAA==.',
Ho='Holygral:BAAANQABCggIFAABNQAFFAIIBgAgAIwfAA==.Holymun:BAAANQAECgcICQAAAA==.Holyox:BAABNQAECn85AAIJAAoKvgZ41wBtAQAJAAoKvgZ41wBtAQAAAA==.Hotcheeto:BAAANQAECgcIBwAAAA==.Hotdog:BAAANQADCgQIBAAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.Hturtledk:BAAANQAECggIDAAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECggICgABAAAAAA==.',
['Hü']='Hüntress:BAABNQAECn8ZAAIhAAoK9QcMpgBnAQAhAAoK9QcMpgBnAQAAAA==.',
Ig='Ignuskore:BAAANQAECgEIAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECgoKFQARAAYcAA==.Imgibby:BAABNQAECn8cAAITAAgKGRBmcACLAQATAAgKGRBmcACLAQABNQAECgoKQgAdAFsbAA==.',
In='Inexorable:BAACNQAFFH8JAAIJAAIKOx3YIACeAAAJAAIKOx3YIACeAAA1AAQKfzEAAgkACQrRJKokAM4CAAkACQrRJKokAM4CAAAA.Inssaane:BAAANQADCggIDgAAAA==.Interesting:BAAANQADCgYIBgAAAA==.',
Io='Iolegnaro:BAABNQAECn8WAAIUAAcKMyS+cgCYAgAUAAcKMyS+cgCYAgABNQAFFAgIFgAbAJ4iAA==.',
Ir='Irakwa:BAAANQAECgEIAQAAAA==.Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAACNQAFFH8dAAIZAAgKeR/cAgBNAgAZAAgKeR/cAgBNAgA1AAQKfzkAAhkACgo1JucDAJcDABkACgo1JucDAJcDAAAA.',
Iz='Izry:BAABNQAECn8fAAQFAAoKQRWvNQBwAQAEAAkKORAqOwDiAQAFAAYK/RWvNQBwAQAYAAQKjQ0YoQC5AAAAAA==.Izánámi:BAAANQADCggICAABNQAECggIJwASAC0LAA==.',
Ja='Jaason:BAABNQAECn84AAMEAAkK5xqRKABUAgAEAAkKnhmRKABUAgAFAAgK+xOKNgBsAQAAAA==.Jalen:BAAANQADCgYIBgAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQAECgUICwABNQAECggICQABAAAAAA==.',
Jh='Jhora:BAABNQAECn8eAAIbAAoKGhoiHgCBAgAbAAoKGhoiHgCBAgAAAA==.Jhunts:BAAANQAECgYICwAAAA==.',
Ji='Jinfizz:BAAANQAECgIIAgAAAA==.Jinfuse:BAABNQAECn8xAAMUAAoKyRl4kwBZAgAUAAoK5hh4kwBZAgAVAAEKDBw9OwBSAAAAAA==.',
Jo='Jormungandr:BAAANQADCgIIAgAAAA==.',
Jp='Jpdh:BAABNQAECn9FAAQOAAoKAST4EAAYAwAOAAoKOh74EAAYAwAPAAgK3iKYCADwAQACAAoKGRvqGADpAQAAAA==.Jpdumb:BAAANQAECgUIBQABNQAECgoKRQAOAAEkAA==.',
Ju='Juddory:BAABNQAECn8gAAIUAAcKdQwWxAAfAQAUAAcKdQwWxAAfAQAAAA==.Junksvil:BAABNQAECn8YAAMIAAcKyRslHgD4AQAIAAcKyRslHgD4AQAJAAQKIAoJNQGdAAABNQAECggICQABAAAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Ka='Kalystia:BAAANQABCgIIAgAAAA==.',
Ke='Kealthara:BAAANQAECgQIBAAAAA==.',
Kh='Khalyon:BAABNQAECn80AAIUAAoK8BmKbQCjAgAUAAoK8BmKbQCjAgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.',
Ko='Koa:BAAANQAECgEIAQAAAA==.Koppel:BAABNQAECn8kAAMRAAkKAw0VNAC7AAASAAYKWg0IgwAfAQARAAcKiQkVNAC7AAABNQAECgoKNgAhALMXAA==.Korinth:BAECNQAFFH8OAAIJAAcKigljDAAoAQAJAAcKigljDAAoAQA1AAQKfzoAAwkACgqqGylRAKICAAkACgqqGylRAKICAAgAAwoiF4tWAIcAAAAA.',
Kr='Kriaalis:BAAANQAECggIEAAAAA==.',
Ku='Kunitsu:BAAANQAECgQICwAAAA==.',
Ky='Kyra:BAABNQAECn8fAAMaAAgK+xaLOgAtAgAaAAgK+xaLOgAtAgAbAAIKJgQIBwEuAAAAAA==.Kyril:BAABNQAECn8qAAIJAAkK3yPEGQBdAwAJAAkK3yPEGQBdAwAAAA==.',
['Kæ']='Kælas:BAAANQADCgUIBQAAAA==.',
La='Lagabriela:BAABNQAECn8uAAIFAAkK7QvMSAAZAQAFAAkK7QvMSAAZAQAAAA==.Lazuli:BAAANQADCgQIBAABNQAECgoKRQAOADshAA==.',
Le='Legault:BAABNQAECn88AAIiAAoKPxgfAgAuAgAiAAoKPxgfAgAuAgAAAA==.Legionofboom:BAAANQAECgEIAQAAAA==.Lemanruss:BAAANQADCgQIBAAAAA==.Lethfel:BAAANQAECgcIEgAAAA==.',
Li='Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQAECgIIAgAAAA==.Lionfury:BAAANQAECgQICQABNQAFFAQICwAJAGUGAA==.Lionguard:BAACNQAFFH8LAAIJAAQKZQbjHgCkAAAJAAQKZQbjHgCkAAA1AAQKfyUAAgkACgrwFMWGABoCAAkACgrwFMWGABoCAAAA.Livie:BAABNQAECn8ZAAIJAAgKnxA9twBjAQAJAAgKnxA9twBjAQAAAA==.Lizzard:BAAANQAECgYIBgABNQAFFAQIBgAhANEUAA==.',
Lo='Loca:BAABNQAECn8zAAIaAAoK1wf9iQBxAQAaAAoK1wf9iQBxAQAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loraddesmos:BAABNQAECn9BAAMWAAoKzxFCBADYAQAWAAoKzxFCBADYAQAcAAIKcwX0HgEtAAAAAA==.Loáth:BAAANQADCgcIBwABNQAECggIDgABAAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.Lullaby:BAAANQAECgcICAAAAA==.',
Ly='Lyship:BAAANQAECgQIBgAAAA==.',
Ma='Maeg:BAAANQAECgYICgABNQAECgoKFQARAAYcAA==.Mahll:BAABNQAECn82AAIcAAoKmB+OGwCqAgAcAAoKmB+OGwCqAgAAAA==.Maidenchina:BAAANQAECgMIAwAAAA==.Maleveck:BAAANQAECgYIBgAAAA==.Marcato:BAAANQADCgQIBQABNQAECgYIDAABAAAAAA==.Marcdofu:BAAANQAECgQICQAAAA==.Mardista:BAAANQADCgYIBgAAAA==.',
Mc='Mctanker:BAAANQAECgcIDwAAAA==.',
Me='Meascii:BAABNQAECn9HAAMTAAoKkCHOCwBkAwATAAoKkCHOCwBkAwAjAAgKvg7iCQCxAQAAAA==.Megavolt:BAAANQADCggICAABNQAFFAgIHQAZAHkfAA==.Megs:BAAANQADCggJEwAAAA==.Memebeams:BAAANQAECgQIBQAAAA==.Merc:BAACNQAFFH8MAAIZAAcKlwpeCQDiAAAZAAcKlwpeCQDiAAA1AAQKfz0AAhkACgorIS0JANQCABkACgorIS0JANQCAAAA.',
Mi='Miluo:BAAANQAECgMIBQABNQAECgkJJgAhAMMiAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBAAAAA==.Miredagger:BAAANQADCgEIAQABNQAFFAcIEgAgAP8WAA==.Mirefighter:BAAANQAECgUICAABNQAFFAcIEgAgAP8WAA==.Mirespike:BAACNQAFFH8SAAMgAAcK/xYnAQAaAQAgAAcK/xYnAQAaAQAHAAEKxQJQJQA3AAA1AAQKfzYAAyAACgroIhAFADMDACAACgroIhAFADMDAAcAAgqzGGqAAEYAAAAA.Mistbrew:BAAANQAECgYICwABNQAECgoKFwAQAGQVAA==.Miushi:BAEANQAECgUIBQABNQAFFAcIDgAJAIoJAA==.',
Mj='Mjoinir:BAAANQAECgUIBgAAAA==.',
Mo='Modin:BAABNQAECn8XAAITAAcKaxHvcwB/AQATAAcKaxHvcwB/AQABNQAECggIJQADAC4UAA==.Mommacougar:BAAANQADCgIIAgAAAA==.Moon:BAAANQADCgUICgABNQADCgcIGwABAAAAAA==.Morawynd:BAABNQAECn8WAAMGAAQKhgHobgBHAAAGAAQKhgHobgBHAAAHAAIKYgCgmgAVAAAAAA==.Morlis:BAAANQAECgQICwAAAA==.Morlock:BAABNQAECn8vAAIcAAoKAgpzlgCuAQAcAAoKAgpzlgCuAQAAAA==.Morningstahr:BAABNQAECn8iAAIUAAoKMxjxigBpAgAUAAoKMxjxigBpAgAAAA==.Morphìc:BAAANQAECgUIBgAAAA==.',
Mu='Munion:BAAANQAECgQJBAABNQAECgcICQABAAAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Mô']='Môrningstar:BAAANQADCgUIBQAAAA==.',
Na='Naanbread:BAAANQAECgYIBgAAAA==.Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQAECgQIBAAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyfused:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyvoked:BAAANQAECgUIBAABNQAECgUIDAABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEIAQAAAA==.',
Ni='Nickayla:BAABNQAECn8aAAIWAAYKoQc9GgCSAAAWAAYKoQc9GgCSAAAAAA==.Nikkaya:BAAANQADCgYJBgABNQAECggIFwAfACoWAA==.Nimblecow:BAAANQADCgMIBAAAAA==.',
No='Noobacleese:BAABNQAECn8yAAIJAAoKFRo5jAANAgAJAAoKFRo5jAANAgAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.Novarak:BAAANQADCgMIAwAAAA==.Noyn:BAAANQAECgEIAQABNQAECgkJJgAhAMMiAA==.',
Ny='Nyghtrider:BAAANQAECgUIEAAAAA==.Nymëra:BAABNQAECn8ZAAIaAAkKoAwrmABKAQAaAAkKoAwrmABKAQAAAA==.Nyneeve:BAABNQAECn8rAAIKAAoKTwzaGgDDAQAKAAoKTwzaGgDDAQAAAA==.',
Od='Odinshunter:BAAANQAECgIIAgAAAA==.Odst:BAAANQAECgIIBAABNQAECgoKMgAEAFoZAA==.',
Ol='Olgrin:BAAANQADCgUIBQABNQAECgMIBAABAAAAAA==.',
On='Onepunch:BAAANQADCgcIBwAAAA==.Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQAECgEIAgAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBQAAAA==.Pandaloons:BAAANQABCgYICAABNQADCgYIBgABAAAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQAECgYIDAAAAA==.',
Pb='Pbób:BAAANQAECggIEAAAAA==.',
Pe='Percocetpete:BAABNQAECn8sAAMTAAoKKyTgEgA0AwATAAoKKyTgEgA0AwAKAAgKRgcKNQB7AQAAAA==.Peregrine:BAAANQAECgEIAQAAAA==.',
Ph='Phaet:BAACNQAFFH8QAAMcAAcKGBZyDwA5AQAcAAYK1RZyDwA5AQAWAAEKJxNQEQBLAAA1AAQKfzQAAxwACgpuIVk4AKsCABwACQrLIVk4AKsCABYABAoHFRgyAP0AAAAA.Phaux:BAAANQAECgIIBQAAAA==.',
Pi='Piper:BAABNQAECn8mAAMTAAoKJw31agCdAQATAAoKJw31agCdAQAKAAUK7gNlWQCjAAAAAA==.',
Pl='Plâgue:BAABNQAECn9HAAMYAAoK9CEbCwDHAgAYAAoK9CEbCwDHAgAEAAUKYxBLawDwAAAAAA==.',
Pr='Prot:BAAANQADCgUIBQAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgoKPQAgAOomAA==.Puntthegnome:BAAANQADCgEIAQABNQAFFAgIGwAUAFYRAA==.',
Qu='Quackas:BAAANQADCgYIBgAAAA==.',
Ra='Rainforest:BAABNQAECn8XAAMfAAgKKhbWJABvAQAfAAcKehfWJABvAQAgAAIKnw9+SwAxAAAAAA==.Raktox:BAAANQADCggICgAAAA==.Ramden:BAABNQAECn86AAIJAAoKgwiE1wBsAQAJAAoKgwiE1wBsAQAAAA==.Rampant:BAABNQAECn8yAAQEAAoKWhmDGwBtAgAEAAoKWhmDGwBtAgAFAAMKKQxVqACBAAAYAAIKBBNevgBuAAAAAA==.Rampscii:BAABNQAECn8lAAMTAAoKSyJiFAA1AwATAAoKSyJiFAA1AwAKAAUKKgyhQgCkAAABNQAECgoKMgAEAFoZAA==.Randalthorr:BAAANQADCgUIBQAAAA==.Randolier:BAABNQAECn8xAAMhAAoKtSACKgDwAgAhAAoKtSACKgDwAgAkAAEK5AP4dQAkAAAAAA==.Ratherton:BAACNQAFFH8bAAMUAAgKVhEVEAD2AQAUAAcKPhQVEAD2AQAVAAEKywKpFQBGAAA1AAQKf1IAAxQACgp4IwETAP8CABQACgpiIwETAP8CABUAAQr0I0AxAGcAAAAA.Rathtard:BAABNQAECn8uAAIhAAoKtR2rOABpAgAhAAoKtR2rOABpAgABNQAFFAgIGwAUAFYRAA==.Rauzer:BAAANQABCgIIAgAAAA==.Razz:BAAANQABCgIIAgAAAA==.',
Re='Renuwu:BAABNQAECn9dAAITAAoKpRMORQAkAgATAAoKpRMORQAkAgAAAA==.Reqper:BAAANQADCgMIAwAAAA==.Resoluteone:BAABNQAECn9MAAIFAAoKiggiQgA1AQAFAAoKiggiQgA1AQAAAA==.Retnu:BAAANQADCgQIDAAAAA==.Retrograde:BAAANQAECggIEAAAAA==.Revelations:BAAANQAECgMIAwABNQAECgoKKQAaAM0kAA==.Revytwohand:BAACNQAFFH8SAAIZAAcKoBDDBgAsAQAZAAcKoBDDBgAsAQA1AAQKfzwAAxkACgrqIM8NAIACABkACgrqIM8NAIACACUAAQpSGb05AEkAAAAA.',
Rh='Rhok:BAAANQAECgQIDwAAAA==.',
Ro='Robonome:BAAANQADCgUIBQAAAA==.Roker:BAAANQAECgMIBAABNQAECgoKNgAhALMXAA==.',
Ru='Rumii:BAAANQAECgYICgAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
['Rö']='Rödrïck:BAAANQAECgYICgABNQAECgoKRQAcADsdAA==.',
Sa='Sabeladys:BAABNQAECn8fAAIJAAoKvgxFzQA8AQAJAAoKvgxFzQA8AQAAAA==.Saifir:BAABNQAECn8uAAMaAAgKmgsFpAAsAQAaAAgKmgsFpAAsAQAbAAUK3hAIvwAUAQAAAA==.Sallyd:BAAANQAECgEIAQAAAA==.Sardmagia:BAAANQAECgIIAgABNQAECgUJDAABAAAAAA==.Sardmongo:BAAANQAECgEIAQAAAA==.Sarduccini:BAAANQAECgUJDAAAAA==.',
Se='Sersi:BAAANQADCgQIBAAAAA==.',
Sh='Shadowpriest:BAAANQABCgIIAgAAAA==.Shamwowzer:BAAANQADCgQIBAAAAA==.Shelisaria:BAAANQAECgcIDAAAAA==.Shiftken:BAAANQADCgMIAwAAAA==.Shoktherapy:BAABNQAECn9LAAMaAAoKRSGHBwChAwAaAAoKRSGHBwChAwAbAAIKAAAHOAEyAAAAAA==.',
Si='Silvalus:BAAANQAECgMIBAAAAA==.Silvertide:BAABNQAECn9CAAMbAAoKexR5NAAEAgAbAAoKexR5NAAEAgAaAAgKaw6IiwBtAQAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skonka:BAAANQADCggICAAAAA==.Skyeforce:BAAANQADCggIDgAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
Sm='Smargaid:BAAANQAECgEIAQAAAA==.',
So='Soi:BAABNQAECn8mAAMhAAkKwyIqLwDfAgAhAAkKwyIqLwDfAgAkAAIKJA0BdABpAAAAAA==.Solas:BAAANQAECgUICQAAAA==.Solvent:BAAANQADCggICwAAAA==.Sondaar:BAAANQABCgcIDwAAAA==.Sonoforak:BAAANQAECgMJAwAAAA==.',
Sp='Sped:BAABNQAECn8xAAIXAAoKKSADBgALAwAXAAoKKSADBgALAwAAAA==.',
St='Staraleena:BAAANQAECgUIBAAAAA==.Stiffyhaze:BAAANQAECgQIBAAAAA==.Stillwët:BAAANQABCggICwAAAA==.Stingyr:BAABNQAECn8rAAIhAAkK/AmMjQCcAQAhAAkK/AmMjQCcAQAAAA==.Stormslight:BAAANQAECgYIEgAAAA==.Stormsteel:BAAANQAECgIIAQAAAA==.Stossel:BAABNQAECn82AAIhAAoKsxegOwBhAgAhAAoKsxegOwBhAgAAAA==.Stôrmrägé:BAAANQAECgMIAwAAAA==.',
Su='Subconscious:BAAANQAECgMIBAAAAA==.Sulfion:BAAANQADCgEIAQAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Sy='Sylvänäs:BAAANQAECgIIAQAAAA==.',
Ta='Tab:BAAANQADCgQIAQAAAA==.Tabio:BAAANQADCgYIBwAAAA==.Taboptics:BAAANQAECgUIBAAAAA==.Tabs:BAAANQADCgEIAQAAAA==.Taby:BAAANQADCgEIAQAAAA==.Talas:BAABNQAECn8xAAIIAAoKShnNGwAPAgAIAAoKShnNGwAPAgAAAA==.Tamarack:BAAANQAECgUICAAAAA==.Tanksabunch:BAABNQAECn8eAAIeAAoKFhb6gACFAQAeAAoKFhb6gACFAQABNQAFFAgIHQAkAMchAA==.',
Te='Tegoz:BAABNQAECn8eAAIgAAoKiBdMCgA4AgAgAAoKiBdMCgA4AgAAAA==.Tehmay:BAAANQADCgIIAgAAAA==.Temocratus:BAAANQADCgEIAQABNQAECgMIBAABAAAAAA==.Tenssid:BAAANQADCggIGAAAAA==.Terrormisu:BAAANQAECgcICQABNQAECgoKNAAJACQbAA==.',
Th='Thorclap:BAAANQAECgEJAQAAAA==.Thundertaker:BAAANQADCgYICgAAAA==.',
Ti='Tim:BAAANQADCggICgABNQAECgoKMAAQALcdAA==.Tiniashio:BAAANQAECgQIBAABNQAECgcILgAcADIMAA==.',
To='Tooru:BAACNQAFFH8GAAMhAAQK0RSKFwDXAAAhAAMK0RSKFwDXAAAkAAEKAAAYJgAAAAA1AAQKf0wABCEACgqCJZMMACkDACEACgqCJZMMACkDACQACAqoD341AKIBACYABgp4FXIIAHsBAAAA.',
Tr='Traest:BAAANQAECgEIAgAAAA==.Treebeef:BAAANQAECgMIAwAAAA==.Triena:BAAANQADCggJCAAAAA==.Trimas:BAAANQAECgEIAQAAAA==.',
Tt='Tt:BAABNQAECn8YAAQEAAcK8CPBHABjAgAEAAcK8CPBHABjAgAYAAEKsxu4zABTAAAFAAEKZAAAAAAAAAAAAA==.',
Tw='Twinkles:BAABNQAECn8lAAMDAAgKLhQ/WwAHAgADAAgKLhQ/WwAHAgAJAAMK+Au1igE+AAAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ty='Typicaldrood:BAAANQAECgMIAwAAAA==.Typicalmonk:BAAANQADCgQIBAAAAA==.',
Ul='Ulysius:BAABNQAECn81AAIJAAoKQhP1hADCAQAJAAoKQhP1hADCAQAAAA==.',
Va='Valkisek:BAABNQAECn8fAAIVAAoKuhZnBwB6AgAVAAoKuhZnBwB6AgAAAA==.Vallarfax:BAABNQAECn8kAAIhAAkKdhlmUAB+AgAhAAkKdhlmUAB+AgAAAA==.Vandro:BAABNQAECn9CAAMDAAoKbBQkTwDXAQADAAoKbBQkTwDXAQAIAAYKpgkROADPAAAAAA==.Varea:BAABNQAECn8UAAITAAcKphE1kwBcAQATAAcKphE1kwBcAQABNQAECgoKRgAUABgaAA==.Vashdk:BAACNQAFFH8SAAIFAAcKSB06CwBfAQAFAAcKSB06CwBfAQA1AAQKfzIAAgUACgqzJIgIAHYDAAUACgqzJIgIAHYDAAAA.',
Ve='Velcyn:BAABNQAECn8dAAMcAAoKISMoHwAIAwAcAAoKISMoHwAIAwAWAAEKNROEdQA4AAAAAA==.Veloranas:BAABNQAECn9GAAMUAAoKGBrnQwBBAgAUAAoKDRrnQwBBAgAVAAMK3xGTKwCeAAAAAA==.Venjince:BAAANQADCgYIBgAAAA==.Venôm:BAAANQADCgQIBQAAAA==.Vespyr:BAABNQAECn8qAAIhAAgK2g6blACMAQAhAAgK2g6blACMAQABNQAECgkJKwAhAPwJAA==.Vewdoo:BAABNQAECn9EAAIbAAoKySP/DQB5AwAbAAoKySP/DQB5AwAAAA==.Vexiara:BAAANQADCgcIDwABNQAECggICgABAAAAAA==.',
Vi='Vizimir:BAABNQAECn8aAAIVAAYKBwuiJgC9AAAVAAYKBwuiJgC9AAAAAA==.',
Vy='Vynstabbin:BAAANQAECgUICgABNQAECggIDQABAAAAAA==.',
Wa='Waiwai:BAAANQAECggIEQAAAA==.Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAABNQAECn8rAAIhAAoK5RcwPQBdAgAhAAoK5RcwPQBdAgABNQAECgoKMgAEAFoZAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wh='Whiskeybear:BAAANQADCgYICAAAAA==.',
Wi='Wickedsinner:BAAANQAECgEIAQAAAA==.Wigglesimps:BAAANQAECgEIAQABNQAECggICQABAAAAAA==.Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wivvy:BAABNQAECn8fAAILAAoKww1fCgDGAQALAAoKww1fCgDGAQAAAA==.Wizkerbizkit:BAABNQAECn8oAAMhAAkKTAreiwCfAQAhAAcKJgreiwCfAQAkAAYKAQkETQD9AAAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wooshira:BAAANQAECgEIAQAAAA==.',
Wy='Wyrmheal:BAABNQAECn9GAAIKAAoKXiLwBAApAwAKAAoKXiLwBAApAwAAAA==.Wyvvie:BAABNQAECn8mAAIlAAoKRBekDABiAgAlAAoKRBekDABiAgAAAA==.',
Ya='Yamihime:BAABNQAECn86AAMOAAoK3xm0IQCOAgAOAAoK3xm0IQCOAgACAAIKvg+AVgA1AAAAAA==.Yatiri:BAAANQAECgcIDQAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.Zambas:BAAANQAECgMIAwAAAA==.',
Ze='Zeaket:BAACNQAFFH8jAAImAAgKRB8VAAAiAgAmAAgKRB8VAAAiAgA1AAQKf0IAAiYACgqVJhgAAJoDACYACgqVJhgAAJoDAAAA.Zef:BAAANQAECgQIBAAAAA==.Zephyr:BAAANQAECgQICAABNQAECgkJKwAhAPwJAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQAECggICQABNQAECgkJJgAhAMMiAA==.',
Zo='Zorcan:BAABNQAECn8gAAIdAAgKGRqzCQCzAQAdAAgKGRqzCQCzAQAAAA==.',
Zu='Zugzugz:BAAANQAECggICAAAAA==.Zulfilith:BAAANQAECgQICgAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Àr']='Àrrhythmia:BAABNQAECn8VAAIdAAkKHwp7DAB4AQAdAAkKHwp7DAB4AQABNQAECgoKSwAaAEUhAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Än']='Äncïênt:BAAANQADCgcIBwAAAA==.',
['Ær']='Ærwn:BAAANQAECgQIBAAAAA==.',
['Ða']='Ðachee:BAABNQAECn85AAQTAAoKkiAnGwD/AgATAAoKkiAnGwD/AgAjAAEKshR3FwBBAAAKAAEKAADIegAAAAAAAA==.',
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
