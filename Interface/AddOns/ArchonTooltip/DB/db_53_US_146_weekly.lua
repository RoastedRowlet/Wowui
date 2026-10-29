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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Paladin-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Paladin-Protection','Paladin-Retribution','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','Shaman-Enhancement','Rogue-Assassination','Priest-Holy','Warlock-Affliction','Mage-Arcane','Rogue-Subtlety','Monk-Windwalker','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance','Druid-Feral','Druid-Guardian','Hunter-BeastMastery','DeathKnight-Unholy','Rogue-Outlaw','Priest-Discipline','Hunter-Marksmanship','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aadrik:BAAANQADCggICAAAAA==.',
Ad='Adrenalin:BAAANQAECgYIEgAAAA==.Adversary:BAAANQADCgcICQAAAA==.',
Ae='Aennish:BAAANQABCgIIBgAAAA==.Aerfen:BAAANQAECgEIAQAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIEAAAAA==.',
Ai='Airibeth:BAAANQAECgMIAgAAAA==.Aiyanna:BAAANQAECgMIAwABNQAECgUIEAABAAAAAA==.',
Al='Alric:BAABNQAECn8qAAICAAoKDxk5CwA/AgACAAoKDxk5CwA/AgAAAA==.Althalos:BAAANQABCgQIBgAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQAECgUIBgAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Arator:BAAANQAECgEIAQAAAA==.Ardhammer:BAAANQAECgQJBAAAAA==.Arragorn:BAABNQAECn8eAAIDAAoKNQ62ZADqAQADAAoKNQ62ZADqAQAAAA==.',
As='Asendra:BAAANQAECgQICgAAAA==.Astal:BAACNQAFFH8QAAMEAAUKxxaACwArAQAEAAQKxxaACwArAQAFAAEKAADBIQAAAAA1AAQKfy8AAgQACgpkIqASAPkCAAQACgpkIqASAPkCAAAA.Asunder:BAAANQAECgEIAQAAAA==.',
At='Ate:BAABNQAECn8kAAMGAAoKgxOCJwDkAQAGAAoKgxOCJwDkAQAHAAIKJQYzYgBNAAAAAA==.',
Au='Aurathur:BAABNQAECn8ZAAMIAAcKVRhOIQDZAQAIAAcKVRhOIQDZAQAJAAEKAAAhpgE0AAAAAA==.',
Av='Avasilva:BAAANQAECgEIAQAAAA==.Avyl:BAAANQADCgEJAQABNQAECgIIAwABAAAAAA==.',
Ay='Ayannar:BAAANQAECgEIAQAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECgcICwABAAAAAA==.Azriella:BAABNQAECn8VAAIKAAcKOwzBHwAKAQAKAAcKOwzBHwAKAQAAAA==.Azuren:BAABNQAECn8sAAMLAAkKtg3vCQBSAQALAAkKtg3vCQBSAQAMAAIKkgW6EwBFAAAAAA==.',
Ba='Bacon:BAABNQAECn86AAINAAoKcCDfGQDMAgANAAoKcCDfGQDMAgAAAA==.Bamboozled:BAAANQADCgQIBAABNQAECgcIEwABAAAAAA==.Bankai:BAABNQAECn8qAAIOAAkKZSO/BABFAwAOAAkKZSO/BABFAwAAAA==.',
Be='Beardedtroll:BAABNQAECn8UAAIPAAkKRR5JDQAaAwAPAAkKRR5JDQAaAwAAAA==.Beefstrasz:BAACNQAFFH8QAAIQAAUKrgReDwA1AQAQAAUKrgReDwA1AQA1AAQKfzQAAhAACgpvFE9TACkCABAACgpvFE9TACkCAAAA.Beyla:BAABNQAECn8dAAIJAAoKvgwlWwCmAQAJAAoKvgwlWwCmAQAAAA==.',
Bh='Bhalecgos:BAAANQADCgYIEAAAAA==.',
Bi='Bishamon:BAAANQAECgIIBgAAAA==.',
Bl='Blank:BAAANQAECgMIBAAAAA==.Blazethorn:BAAANQAECgEIAQAAAA==.Bleau:BAAANQAECgYIDQAAAA==.Blethings:BAAANQADCgYIBgABNQAECggIEwARAN8ZAA==.Bloodhornbob:BAAANQADCgUIDgAAAA==.Bloodimary:BAAANQADCgIIAgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodráyne:BAAANQADCgMIAwAAAA==.Bloodymary:BAABNQAECn81AAIFAAoKIxPUGQDHAQAFAAoKIxPUGQDHAQAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAABNQAECn8zAAISAAoKYhPNOQAMAgASAAoKYhPNOQAMAgAAAA==.Bláze:BAAANQADCggICAABNQAECggIGQATABIKAA==.Blôodräge:BAAANQAECgYICgAAAA==.',
Bo='Bomm:BAAANQAECgEIAgAAAA==.Boolzeye:BAAANQABCgQICAAAAA==.Bouncy:BAAANQAECgIIAgAAAA==.Bowl:BAACNQAFFH8QAAIIAAUK3Bz+AwDSAAAIAAUK3Bz+AwDSAAA1AAQKfzQAAggACgryIqIIABMDAAgACgryIqIIABMDAAAA.',
Br='Branchling:BAAANQAECgYIBgABNQAFFAcIGAASAEQSAA==.Breaklimit:BAAANQADCggIDQAAAA==.',
Bu='Butterkip:BAACNQAFFH8TAAIKAAYKKgzuAwAuAQAKAAYKKgzuAwAuAQA1AAQKfyUAAgoACgrBGx8YAJMCAAoACgrBGx8YAJMCAAAA.',
Ce='Cellan:BAAANQADCgYIEwAAAA==.',
Ch='Chewdawgg:BAAANQAECgYIBwAAAA==.Chewdogg:BAAANQAECggICAAAAA==.Cheww:BAABNQAECn8pAAMQAAoKsBbfPADCAQAQAAkK/RbfPADCAQAKAAIKaAx4dQA7AAAAAA==.Chicknburger:BAAANQAECgEIAQAAAA==.Chlorofõrm:BAABNQAECn8ZAAITAAcKEgpZYwDRAAATAAcKEgpZYwDRAAAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Choopamelo:BAAANQADCgEIAQAAAA==.Chopahoe:BAABNQAECn8tAAIUAAoKPR5zEgDIAgAUAAoKPR5zEgDIAgAAAA==.Chudlock:BAAANQADCggIDwABNQAECgoKRwAQALAkAA==.Chumpcooker:BAAANQADCgYICAAAAA==.',
Cl='Clamius:BAACNQAFFH8RAAMVAAYKeiMYBQDAAAASAAQK0Ba2NQDuAAAVAAMKbyQYBQDAAAA1AAQKfzcAAxIACgqTI9YiAFEDABIACgpYItYiAFEDABUAAwqjJQsMAEcBAAAA.Cliff:BAABNQAECn8tAAIWAAoK4CLgDQBSAwAWAAoK4CLgDQBSAwAAAA==.',
Co='Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAABNQAECn8pAAMWAAoKzSShBACkAwAWAAoKzSShBACkAwAXAAgKnBwXLwC/AgAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cortex:BAAANQADCgIIAgAAAA==.Cosmic:BAAANQADCgYIBgAAAA==.Cotopla:BAABNQAECn8XAAISAAcK0A9E9QChAQASAAcK0A9E9QChAQAAAA==.',
Cr='Crimsondream:BAABNQAECn8gAAMYAAcKkgp/dgAMAQAYAAcKkgp/dgAMAQAZAAEKAAAAfgAvAAAAAA==.',
Da='Daemea:BAAANQAECgIIAgAAAA==.Dagov:BAAANQAECgIIAgAAAA==.Darkart:BAAANQADCgYICgAAAA==.Darkshivers:BAAANQADCgcIBwABNQAECgEIBAABAAAAAA==.Darkswarm:BAAANQAECgIIAgAAAA==.',
De='Deathlentlez:BAABNQAECn8tAAIaAAoKxRjUCADDAQAaAAoKxRjUCADDAQAAAA==.Decaylentlez:BAAANQAECgEIAQABNQAECgoKLQAaAMUYAA==.Deepséeded:BAAANQADCgEIAQABNQAECgkJKQAWAO4hAA==.Delphyne:BAABNQAECn8hAAILAAkKTAjMCgA9AQALAAkKTAjMCgA9AQAAAA==.Demonhunter:BAAANQAECgQICgAAAA==.Demonià:BAABNQAECn8aAAMVAAcKEASILACYAAASAAcKdAOntgDaAAAVAAQK3gSILACYAAAAAA==.Dewhey:BAAANQAECgUIBQABNQAECgoKNQAFACMTAA==.',
Di='Diamondsword:BAAANQAECggIEwAAAA==.Dinkleberg:BAAANQAECgEIAQAAAA==.Disçiple:BAAANQAECgEIAwABNQAECgkJKQAWAO4hAA==.',
Dj='Djazz:BAAANQAECgIIAwAAAA==.',
Dr='Drewsan:BAABNQAECn8XAAIbAAkKBw0tXwBlAQAbAAkKBw0tXwBlAQAAAA==.Drowsee:BAABNQAECn8YAAIMAAcK/gwCEQAmAQAMAAcK/gwCEQAmAQAAAA==.',
Du='Dulcinea:BAAANQAECgUIDQAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
['Dú']='Dúncan:BAAANQADCggIFwAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAABNQAECn8zAAMNAAoKdRriDwBOAgANAAoKrRjiDwBOAgAcAAcKZh11CwAYAgAAAA==.',
Ei='Eirinny:BAAANQADCggIDgAAAA==.',
El='Elindez:BAABNQAECn8VAAITAAoKKgy3TQAmAQATAAoKKgy3TQAmAQAAAA==.Elyviel:BAAANQAECgcICwAAAA==.',
En='Encantado:BAAANQAECgEIAwAAAA==.End:BAAANQADCggICAAAAA==.Endlesswaltz:BAAANQADCgcIBwAAAA==.',
Eo='Eowen:BAABNQAECn8pAAIDAAoKUQ0ZOAC9AQADAAoKUQ0ZOAC9AQAAAA==.',
Ep='Epitaph:BAAANQADCgYICwAAAA==.',
Ez='Ezmee:BAAANQAECgEIAwAAAA==.',
Fa='Faelicia:BAAANQADCgYIFwAAAA==.Falandoria:BAAANQAECgIIAgAAAA==.Fastnfurious:BAAANQAECgUICAABNQAECgoKNQAFACMTAA==.',
Fr='Frostdruid:BAAANQADCgEIAQAAAA==.Frowmae:BAAANQAECgUICQAAAA==.',
Fu='Fundip:BAAANQAECgYIEgAAAA==.',
Fy='Fythra:BAAANQAECgIICAAAAA==.Fythri:BAAANQAECgIIBQABNQAECgIICAABAAAAAA==.',
['Fù']='Fùrìeüx:BAAANQAECgEIAQAAAA==.',
Ga='Gart:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Gawdsmackk:BAAANQAECgQIBAABNQAECgQICwABAAAAAA==.',
Ge='Geolock:BAAANQAECgQIDAAAAA==.',
Gi='Gibbii:BAAANQAECgcICwABNQAECgoKMQARAJcXAA==.Gibdergen:BAAANQAECgYIBgABNQAECgoKMQARAJcXAA==.Gibhasarms:BAAANQADCgYIBgABNQAECgoKMQARAJcXAA==.Giblock:BAABNQAECn8xAAMRAAoKlxfZAwCvAgARAAoKlxfZAwCvAgAZAAEKUwkGLAArAAAAAA==.Ginju:BAABNQAECn8fAAIXAAgK5RpCRABlAgAXAAgK5RpCRABlAgAAAA==.',
Gl='Glamour:BAAANQADCgcIDAABNQAECgYIEgABAAAAAA==.',
Go='Golomojek:BAAANQADCgYICgAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAABNQAECn8wAAIdAAoKqSLzAQABAwAdAAoKqSLzAQABAwAAAA==.Grawfern:BAABNQAECn8vAAMeAAoKlSO4BwAHAwAeAAoKlSO4BwAHAwAHAAYK5QiSawAdAQAAAA==.Graziella:BAAANQADCgYICQABNQAECgYIDAABAAAAAA==.',
Gu='Guldave:BAAANQAECgMIBAAAAA==.Guthrie:BAAANQAECgcIEAAAAA==.',
Gw='Gwÿñ:BAAANQADCgQIBAAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAABNQAECn8pAAIWAAoKwBfyJAAkAgAWAAoKwBfyJAAkAgAAAA==.Harden:BAAANQADCgEIAQAAAA==.Hawktwua:BAAANQAECgEIAQABNQAECgcIFAAIAMkbAA==.',
He='Healforbeer:BAAANQAECgUIBQAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAABNQAECn8nAAIKAAgKCxyFFwCbAgAKAAgKCxyFFwCbAgAAAA==.Hext:BAAANQAECgEIAQABNQAECgoKNwADAOsTAA==.',
Ho='Holygral:BAAANQABCggIFAABNQAECgoKMAAdAKkiAA==.Holylentlezz:BAAANQAECgEIAQABNQAECgoKLQAaAMUYAA==.Holymun:BAAANQAECgcICgAAAA==.Holyox:BAABNQAECn85AAIJAAoKvgZ41wBtAQAJAAoKvgZ41wBtAQAAAA==.Hotcheeto:BAAANQAECgYIBwAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.Hturtledk:BAAANQAECggIDgAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.',
['Hü']='Hüntress:BAABNQAECn8UAAIfAAkKLAdCzwBiAQAfAAkKLAdCzwBiAQAAAA==.',
Ig='Ignuskore:BAAANQAECgEJAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECgkJFAAPAEUeAA==.Imgibby:BAABNQAECn8YAAIQAAcKThEpTQB8AQAQAAcKThEpTQB8AQABNQAECgoKMQARAJcXAA==.',
In='Inexorable:BAACNQAFFH8JAAIJAAIKOx3YIACeAAAJAAIKOx3YIACeAAA1AAQKfy8AAgkACQrNJB4OAAUDAAkACQrNJB4OAAUDAAAA.Inssaane:BAAANQADCggIDgAAAA==.Interesting:BAAANQADCgYIBgAAAA==.',
Io='Iolegnaro:BAABNQAECn8WAAISAAcKMyS+cgCYAgASAAcKMyS+cgCYAgABNQAFFAcIFAAXAOsiAA==.',
Ir='Irakwa:BAAANQAECgEIAgAAAA==.Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAACNQAFFH8cAAIUAAcK4CDcAgBNAgAUAAcK4CDcAgBNAgA1AAQKfzcAAhQACgq6JecDAJcDABQACgq6JecDAJcDAAAA.',
Iz='Izry:BAABNQAECn8fAAQFAAoKQRXbIACMAQAEAAkKORAqOwDiAQAFAAYK/RXbIACMAQAgAAQKjQ0YoQC5AAAAAA==.Izánámi:BAAANQADCggICAABNQAECggIGQATABIKAA==.',
Ja='Jaason:BAABNQAECn8vAAMEAAkK5xqRKABUAgAEAAkK8RiRKABUAgAFAAcK/hMJbwA5AQAAAA==.Jalen:BAAANQAECgEIBQAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQAECgUIDgABNQAECgcIFAAIAMkbAA==.',
Jh='Jhora:BAAANQAECgUIDQAAAA==.Jhunts:BAAANQAECgYIDQAAAA==.',
Ji='Jinfizz:BAAANQAECgIIAgAAAA==.Jinfuse:BAABNQAECn8qAAMSAAoKWRn2SgDQAQASAAoKdhj2SgDQAQAVAAEKDBw9OwBSAAAAAA==.',
Jo='Jormungandr:BAAANQADCgIIAgAAAA==.',
Jp='Jpdh:BAABNQAECn86AAQNAAoKNiP4EAAYAwANAAoK3R34EAAYAwACAAoKOBhNJwAKAgAcAAgK3iKnBAAAAgAAAA==.Jpdumb:BAAANQAECgUIBQABNQAECgoKOgANADYjAA==.',
Ju='Juddory:BAABNQAECn8VAAISAAUK6g932wCcAAASAAUK6g932wCcAAAAAA==.Junksvil:BAABNQAECn8UAAIIAAcKyRslHgD4AQAIAAcKyRslHgD4AQAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Ka='Kalystia:BAAANQABCgIIAgAAAA==.',
Ke='Kealthara:BAAANQAECgQIBQAAAA==.',
Kh='Khalyon:BAABNQAECn80AAISAAoK8BmKbQCjAgASAAoK8BmKbQCjAgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.Kilowatts:BAAANQAECgEIAgAAAA==.',
Ko='Koa:BAAANQAECgEIAwAAAA==.Koppel:BAAANQAECgcIEgABNQAECgkJGgAfAD0TAA==.Korinth:BAECNQAFFH8MAAIJAAUKaAuZEAC/AAAJAAUKaAuZEAC/AAA1AAQKfzAAAwkACgqqGylRAKICAAkACgqqGylRAKICAAgAAgpnH4tWAIcAAAAA.',
Kr='Kriaalis:BAAANQAECgQIBgAAAA==.',
Ku='Kunitsu:BAAANQAECgQICwAAAA==.',
Ky='Kyra:BAAANQAECgUIDQAAAA==.Kyril:BAABNQAECn8qAAIJAAkK3yPEGQBdAwAJAAkK3yPEGQBdAwAAAA==.',
['Kæ']='Kælas:BAAANQADCgUIBQAAAA==.',
La='Lagabriela:BAABNQAECn8sAAIFAAkKbwvZMgAeAQAFAAkKbwvZMgAeAQAAAA==.Lazuli:BAAANQADCgQIBAABNQAECgoKOgANAHAgAA==.',
Le='Legault:BAABNQAECn8oAAIhAAkKhBSvCAAOAgAhAAkKhBSvCAAOAgAAAA==.Legionofboom:BAAANQAECgIIBAAAAA==.Lemanruss:BAAANQADCgQIBAAAAA==.Lethfel:BAABNQAECn8TAAQRAAgK3xm5BQB8AQARAAcKHxi5BQB8AQAYAAQKmhgsyQA4AQAZAAIKhCAsRAC0AAAAAA==.',
Li='Lilgoukii:BAAANQAECgEIAgAAAA==.Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQAECgIIAgAAAA==.Lionfury:BAAANQAECgQICwABNQAFFAMIBgAJAM0FAA==.Lionguard:BAACNQAFFH8GAAIJAAMKzQWlFQCUAAAJAAMKzQWlFQCUAAA1AAQKfyMAAgkACgrdFMWGABoCAAkACgrdFMWGABoCAAAA.Livie:BAAANQAECgQIDwAAAA==.Lizzard:BAAANQAECgUIBQABNQAFFAQIBgAfANEUAA==.',
Lo='Loca:BAABNQAECn8pAAIWAAoKogfiWQAyAQAWAAoKogfiWQAyAQAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loops:BAAANQAECgEIAgAAAA==.Loraddesmos:BAABNQAECn8uAAMZAAoKJA1PAwCVAQAZAAoKJA1PAwCVAQAYAAIKcwV/7QAxAAAAAA==.Loáth:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.Lullaby:BAAANQAECgUIBQAAAA==.',
Ly='Lycanthrope:BAAANQAECgEIBQAAAA==.Lyship:BAAANQAECgQIBgAAAA==.',
Ma='Maeg:BAAANQAECgYIDgABNQAECgkJFAAPAEUeAA==.Mahll:BAABNQAECn8sAAIYAAoK4x1wFACHAgAYAAoK4x1wFACHAgAAAA==.Maidenchina:BAAANQAECgMIBAAAAA==.Maleveck:BAAANQAECgYIBgAAAA==.Marcato:BAAANQADCgQIBQABNQAECgYIDAABAAAAAA==.Marcdofu:BAAANQAECgEIAwAAAA==.Mardista:BAAANQADCgYIBgAAAA==.Mataquay:BAAANQAECgEIAwAAAA==.',
Mc='Mctanker:BAAANQAECgYIDwAAAA==.',
Me='Meascii:BAABNQAECn80AAMQAAoKyR7OCwBkAwAQAAoKyR7OCwBkAwAiAAgKvg7iCQCxAQAAAA==.Megavolt:BAAANQADCggICAABNQAFFAcIHAAUAOAgAA==.Megs:BAAANQADCggJEwAAAA==.Memebeams:BAAANQAECgQICgAAAA==.Merc:BAACNQAFFH8KAAIUAAUKpAsgCwAGAQAUAAUKpAsgCwAGAQA1AAQKfzEAAhQACgrTH5MIAIgCABQACgrTH5MIAIgCAAAA.',
Mi='Miluo:BAAANQAECgMIBQABNQAECgkJIAAfAIIiAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBgAAAA==.Miredagger:BAAANQADCgEIAQABNQAFFAUIEAAdAIgWAA==.Mirefighter:BAAANQAECgMIAwABNQAFFAUIEAAdAIgWAA==.Mirespike:BAACNQAFFH8QAAMdAAUKiBavAQBWAQAdAAUKiBavAQBWAQAHAAEKxQI/GgA9AAA1AAQKfy4AAx0ACgoRIRAFADMDAB0ACgoRIRAFADMDAAcAAgqzGDljAEoAAAAA.Missroxy:BAAANQAECgEIAQAAAA==.Mistbrew:BAAANQAECgYICwABNQAECgoKFwAOAGQVAA==.Miushi:BAEANQAECgEIAQABNQAFFAUIDAAJAGgLAA==.',
Mj='Mjoinir:BAAANQAECgMIAwAAAA==.',
Mo='Modin:BAAANQAECgcIEwABNQAECggIJQADAC4UAA==.Mommacougar:BAAANQADCgIIAgAAAA==.Moon:BAAANQADCgUICgABNQADCgYIFQABAAAAAA==.Morawynd:BAAANQAECgQICgAAAA==.Morlis:BAAANQAECgIIBQAAAA==.Morlock:BAABNQAECn8sAAIYAAoKAgqHagAqAQAYAAoKAgqHagAqAQAAAA==.Morningstahr:BAABNQAECn8iAAISAAoKMxjxigBpAgASAAoKMxjxigBpAgAAAA==.Morphìc:BAAANQAECgUIBgAAAA==.',
Mu='Munion:BAAANQAECgQJBAABNQAECgcICgABAAAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Mô']='Môrningstar:BAAANQAECgEIAQAAAA==.',
Na='Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQAECgEICAAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyfused:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyvoked:BAAANQAECgUIBQABNQAECgUIDAABAAAAAA==.',
Ne='Nevicus:BAAANQAECgEIBAAAAA==.',
Ni='Nickayla:BAABNQAECn8UAAIZAAYKoQeZEACYAAAZAAYKoQeZEACYAAAAAA==.Nikkaya:BAAANQADCgYJBgABNQAECgcIFgAeAHoXAA==.Nimblecow:BAAANQADCgMIBAAAAA==.',
No='Noobacleese:BAABNQAECn8uAAIJAAoKHRneVwCvAQAJAAoKHRneVwCvAQAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.Novarak:BAAANQADCgMIAwAAAA==.Noyn:BAAANQAECgEIAQABNQAECgkJIAAfAIIiAA==.',
Nu='Nueve:BAAANQAECgEIAgAAAA==.',
Ny='Nyghtrider:BAAANQAECgUIEAAAAA==.Nymëra:BAABNQAECn8XAAIWAAgKgwwrmABKAQAWAAgKgwwrmABKAQAAAA==.Nyneeve:BAABNQAECn8gAAIKAAgK3AtBMgCQAQAKAAgK3AtBMgCQAQAAAA==.',
Od='Odinshunter:BAAANQAECgEIAQAAAA==.Odst:BAAANQAECgIIAQABNQAECgoKGwAEANASAA==.',
Ol='Olgrin:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
On='Onepunch:BAAANQADCgcIBwAAAA==.Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQAECgEIAgAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBgAAAA==.Pandaloons:BAAANQAECgEIAwABNQAECgEIBQABAAAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQAECgYIDAAAAA==.',
Pb='Pbób:BAAANQAECggIEgAAAA==.',
Pe='Percocetpete:BAABNQAECn8qAAMQAAoKKyTgEgA0AwAQAAoKKyTgEgA0AwAKAAgKRgcKNQB7AQAAAA==.Peregrine:BAAANQAECgEIAwAAAA==.',
Ph='Phaet:BAACNQAFFH8OAAMYAAUKjRlrFACrAAAYAAQKwBxrFACrAAAZAAEKJxOUCwBRAAA1AAQKfy0AAxgACgpuIVk4AKsCABgACQrLIVk4AKsCABkABAoHFRgyAP0AAAAA.Phaux:BAAANQAECgEIAwAAAA==.',
Pi='Piper:BAABNQAECn8UAAMQAAgKDgXtbQAMAQAQAAgKDgXtbQAMAQAKAAUK7gNlWQCjAAAAAA==.',
Pl='Plâgue:BAABNQAECn82AAMgAAoKSSBpDQBGAgAgAAoKSSBpDQBGAgAEAAEK0hCyhQA8AAAAAA==.',
Pr='Prot:BAAANQADCgUIBQAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgoKMQAdAOomAA==.Puntthegnome:BAAANQADCgEIAQABNQAFFAcIGAASAEQSAA==.',
Qu='Quackas:BAAANQADCgYIBgAAAA==.',
Ra='Rainforest:BAABNQAECn8WAAMeAAcKehfWJABvAQAeAAcKehfWJABvAQAdAAEKAABSRgAtAAAAAA==.Raktox:BAAANQADCggICgAAAA==.Ramden:BAABNQAECn8wAAIJAAoKageE1wBsAQAJAAoKageE1wBsAQAAAA==.Rampant:BAABNQAECn8bAAQEAAoK0BJCIwCzAQAEAAoK0BJCIwCzAQAFAAMKKQxVqACBAAAgAAIKBBNevgBuAAAAAA==.Rampscii:BAABNQAECn8VAAMQAAgKqx0LUAA0AgAQAAgKqx0LUAA0AgAKAAQKPA2HNQB3AAABNQAECgoKGwAEANASAA==.Randolier:BAABNQAECn8tAAMfAAoKZCACKgDwAgAfAAoKZCACKgDwAgAjAAEK5AOSXQAkAAAAAA==.Ratherton:BAACNQAFFH8YAAMSAAcKRBIVEAD2AQASAAYKIhYVEAD2AQAVAAEKywJ0DABOAAA1AAQKfzwAAxIACgpTIgsdAGMDABIACgo9IgsdAGMDABUAAQr0I0kgAG0AAAAA.Rathtard:BAABNQAECn8lAAIfAAoKAxoqJwBGAgAfAAoKAxoqJwBGAgABNQAFFAcIGAASAEQSAA==.Rauzer:BAAANQABCgIIAgAAAA==.Razz:BAAANQAECgEIBgAAAA==.',
Re='Renuwu:BAABNQAECn9LAAIQAAoKBRFpPADEAQAQAAoKBRFpPADEAQAAAA==.Resoluteone:BAABNQAECn82AAIFAAoKBAhuLABAAQAFAAoKBAhuLABAAQAAAA==.Retnu:BAAANQADCgQICwAAAA==.Revelations:BAAANQAECgMIAwABNQAECgoKKQAWAM0kAA==.Revytwohand:BAACNQAFFH8QAAIUAAUK0BlPCQBAAQAUAAUK0BlPCQBAAQA1AAQKfzIAAhQACgrPH08RANYCABQACgrPH08RANYCAAAA.',
Rh='Rhok:BAAANQAECgMIBgAAAA==.Rhokhard:BAAANQAECgEIAQAAAA==.',
Ro='Robonome:BAAANQADCgUIBQAAAA==.',
Ru='Rumii:BAAANQAECgQICQAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
['Rö']='Rödrïck:BAAANQAECgYIDQABNQAECgoKOwAYAPsbAA==.',
Sa='Sabeladys:BAABNQAECn8bAAIJAAoKqwxahABIAQAJAAoKqwxahABIAQAAAA==.Saifir:BAABNQAECn8sAAMXAAgKHxcIvwAUAQAXAAUK3hAIvwAUAQAWAAgKmgvRZAAPAQAAAA==.Sallyd:BAAANQAECgEIAQAAAA==.Santorini:BAAANQAECgEIAQAAAA==.Sardmagia:BAAANQAECgIIAwABNQAECgUJDgABAAAAAA==.Sardmongo:BAAANQAECgEIAgAAAA==.Sarduccini:BAAANQAECgUJDgAAAA==.',
Sh='Shadowpriest:BAAANQAECgEIAwAAAA==.Shamwowzer:BAAANQADCgQIBAAAAA==.Shelisaria:BAAANQAECgYICgAAAA==.Shiftken:BAAANQADCgMIAwAAAA==.Shoktherapy:BAABNQAECn8pAAMWAAkK7iEfBgBrAwAWAAkK7iEfBgBrAwAXAAEKAAAHOAEyAAAAAA==.',
Si='Silvalus:BAAANQAECgIIAgAAAA==.Silvertide:BAABNQAECn8zAAMXAAoKsBJ5IwDkAQAXAAoKsBJ5IwDkAQAWAAgKaw6IiwBtAQAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skonka:BAAANQADCggICAAAAA==.Skyeforce:BAAANQAECgEIBAAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
Sm='Smargaid:BAAANQAECgEIAQAAAA==.',
So='Soi:BAABNQAECn8gAAMfAAkKgiIqLwDfAgAfAAkKgiIqLwDfAgAjAAIKJA0BdABpAAAAAA==.Solas:BAAANQAECgYICgAAAA==.Solvent:BAAANQADCggICwAAAA==.Sondaar:BAAANQABCgcIDQAAAA==.Sonoforak:BAAANQAECgMJBAAAAA==.',
Sp='Sped:BAABNQAECn8uAAIaAAoKFCDCAwCVAgAaAAoKFCDCAwCVAgAAAA==.',
St='Staraleena:BAAANQAECgQIBQAAAA==.Stiffyhaze:BAAANQAECgQIBAAAAA==.Stillwët:BAAANQAECgEIAQAAAA==.Stingyr:BAABNQAECn8XAAIfAAcKeQhbzQBmAQAfAAcKeQhbzQBmAQAAAA==.Stormslight:BAAANQAECgQICAAAAA==.Stormsteel:BAAANQAECgEICAAAAA==.Stossel:BAABNQAECn8aAAIfAAkKPRPMPgDnAQAfAAkKPRPMPgDnAQAAAA==.',
Su='Subconscious:BAAANQAECgIIAwAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Ta='Tab:BAAANQAECgIIAgAAAA==.Tabio:BAAANQADCgYIBwAAAA==.Taboptics:BAAANQAECgQIBgAAAA==.Talas:BAABNQAECn8tAAIIAAoKRRgYEgCEAQAIAAoKRRgYEgCEAQAAAA==.Tamarack:BAAANQAECgUICQAAAA==.Tanksabunch:BAABNQAECn8ZAAIbAAoKhQ0crQCsAQAbAAoKhQ0crQCsAQABNQAFFAgIHQAjAMchAA==.',
Te='Tehmay:BAAANQADCgIIAgAAAA==.Tenssid:BAAANQADCggIGAAAAA==.Terrormisu:BAAANQAECgcICQAAAA==.',
Th='Thorclap:BAAANQAECgEJAQAAAA==.Thundertaker:BAAANQADCgYICgAAAA==.',
Ti='Tim:BAAANQADCggICgABNQAECgoKJwAOAIAdAA==.Tiniashio:BAAANQAECgQIBAABNQAECggIIAAYAJIKAA==.',
To='Tooru:BAACNQAFFH8GAAMfAAQK0RT9DQDkAAAfAAMK0RT9DQDkAAAjAAEKAABlGQAAAAA1AAQKfzwAAx8ACgpUJRkFADwDAB8ACgpUJRkFADwDACMACAqoD341AKIBAAAA.',
Tr='Traest:BAAANQAECgEIBgAAAA==.Treebeef:BAAANQAECgMIAwAAAA==.Triena:BAAANQADCggJCAAAAA==.Trimas:BAAANQAECgEIAwAAAA==.',
Ts='Tsukuyómi:BAAANQAECgEIAQAAAA==.',
Tt='Tt:BAAANQAECggIDQAAAA==.',
Tw='Twinkles:BAABNQAECn8lAAMDAAgKLhQ/WwAHAgADAAgKLhQ/WwAHAgAJAAMK+AvmMQFBAAAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ty='Typicaldrood:BAAANQAECgMIAwAAAA==.Typicalmonk:BAAANQADCgQIBAAAAA==.',
Ul='Ulysius:BAABNQAECn8lAAIJAAoKoRGkmADyAQAJAAoKoRGkmADyAQAAAA==.',
Va='Valkisek:BAABNQAECn8fAAIVAAoKuhZnBwB6AgAVAAoKuhZnBwB6AgAAAA==.Vallarfax:BAABNQAECn8kAAIfAAkKdhlmUAB+AgAfAAkKdhlmUAB+AgAAAA==.Valsera:BAAANQAECgEIAQAAAA==.Vandro:BAABNQAECn83AAIDAAoK6xOiLAD3AQADAAoK6xOiLAD3AQAAAA==.Varea:BAABNQAECn8UAAIQAAcKphEhYQA1AQAQAAcKphEhYQA1AQABNQAECgoKPAASAN0YAA==.Vashdk:BAACNQAFFH8QAAIFAAUKxBwbEABUAQAFAAUKxBwbEABUAQA1AAQKfzAAAgUACgpiJIgIAHYDAAUACgpiJIgIAHYDAAAA.',
Ve='Velcyn:BAABNQAECn8YAAMYAAkKFyIoHwAIAwAYAAkKFyIoHwAIAwAZAAEKNROEdQA4AAAAAA==.Veloranas:BAABNQAECn88AAMSAAoK3RjDNAAeAgASAAoK0RjDNAAeAgAVAAMK3xGTKwCeAAAAAA==.Venjince:BAAANQADCgYIBgAAAA==.Venôm:BAAANQADCgQIBAAAAA==.Vespyr:BAABNQAECn8XAAIfAAcKvw62eABDAQAfAAcKvw62eABDAQABNQAECgcIFwAfAHkIAA==.Vewdoo:BAABNQAECn85AAIXAAoKgSP/DQB5AwAXAAoKgSP/DQB5AwAAAA==.Vexiara:BAAANQADCgcIDwABNQAECgcICwABAAAAAA==.',
Vi='Vivificus:BAAANQAECgEIAgAAAA==.Vizimir:BAABNQAECn8UAAIVAAYKBwuiFQDIAAAVAAYKBwuiFQDIAAAAAA==.',
Vy='Vynstabbin:BAAANQAECgUJCwAAAA==.',
Wa='Waiwai:BAAANQAECgcICAAAAA==.Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAABNQAECn8YAAIfAAoKrQ+EQwDWAQAfAAoKrQ+EQwDWAQABNQAECgoKGwAEANASAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wh='Whiskeybear:BAAANQADCgYICAAAAA==.',
Wi='Wickedsinner:BAAANQAECgEIAgAAAA==.Willowes:BAAANQAECgEIAQAAAA==.Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wivvy:BAABNQAECn8XAAILAAoKdwtABwCsAQALAAoKdwtABwCsAQAAAA==.Wizkerbizkit:BAABNQAECn8fAAMjAAcK0gcETQD9AAAjAAYKAQkETQD9AAAfAAEKEwMnGgEeAAAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wooshira:BAAANQAECgEIAQAAAA==.',
Wy='Wyrmheal:BAABNQAECn88AAIKAAoKWCHqBwBdAwAKAAoKWCHqBwBdAwAAAA==.Wyvvie:BAABNQAECn8dAAIkAAkKHhTxFAAsAgAkAAkKHhTxFAAsAgAAAA==.',
Ya='Yamihime:BAABNQAECn8tAAMNAAoKjBe0IQCOAgANAAoKjBe0IQCOAgACAAEKAAA2bgAxAAAAAA==.Yatiri:BAAANQAECgYIDgAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.Zambas:BAAANQAECgMIAwAAAA==.',
Ze='Zeaket:BAACNQAFFH8gAAIlAAYK0SA5AABRAgAlAAYK0SA5AABRAgA1AAQKfzYAAiUACgo9JscAAJgDACUACgo9JscAAJgDAAAA.Zephyr:BAAANQAECgQIBQABNQAECgcIFwAfAHkIAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQAECggICwABNQAECgkJIAAfAIIiAA==.',
Zi='Zinbad:BAAANQAECgEIAgAAAA==.',
Zo='Zorcan:BAAANQAECgQIDwAAAA==.',
Zu='Zugzugz:BAAANQAECggICAAAAA==.Zulfilith:BAAANQAECgIIAwAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Än']='Äncïênt:BAAANQADCgcIBwAAAA==.',
['Ða']='Ðachee:BAABNQAECn8uAAIQAAkKsiHxDwDyAgAQAAkKsiHxDwDyAgAAAA==.',
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
