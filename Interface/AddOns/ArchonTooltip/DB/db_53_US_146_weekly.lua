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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Paladin-Holy','DeathKnight-Frost','Druid-Restoration','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','Shaman-Enhancement','Rogue-Assassination','Priest-Holy','Paladin-Retribution','DeathKnight-Blood','Mage-Arcane','Paladin-Protection','Priest-Shadow','Monk-Windwalker','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','DemonHunter-Vengeance','Warlock-Affliction','Druid-Feral','Druid-Guardian','Druid-Balance','DeathKnight-Unholy','Rogue-Outlaw','Hunter-BeastMastery','Priest-Discipline','Hunter-Marksmanship','Warrior-Arms','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aadrik:BAAANQADCggICAAAAA==.',
Ad='Adrenalin:BAAANQAECgUIDQAAAA==.Adversary:BAAANQADCgcICQAAAA==.',
Ae='Aennish:BAAANQABCgIIBgAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIEAAAAA==.',
Ai='Airibeth:BAAANQAECgMIAgAAAA==.Aiyanna:BAAANQADCgYIDgABNQAECgUIEAABAAAAAA==.',
Al='Alric:BAABNQAECn8jAAICAAoKShfJAQBvAgACAAoKShfJAQBvAgAAAA==.Althalos:BAAANQABCgQIBgAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQAECgUIBgAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Ardhammer:BAAANQAECgQJBAAAAA==.Arragorn:BAABNQAECn8eAAIDAAoKNQ62ZADqAQADAAoKNQ62ZADqAQAAAA==.',
As='Asendra:BAAANQAECgQICAAAAA==.Astal:BAACNQAFFH8PAAIEAAQKxxboBQDZAAAEAAQKxxboBQDZAAA1AAQKfywAAgQACgpkIqASAPkCAAQACgpkIqASAPkCAAAA.',
At='Ate:BAABNQAECn8eAAIFAAkKdxOCJwDkAQAFAAkKdxOCJwDkAQAAAA==.',
Au='Aurathur:BAAANQAECgYIEQAAAA==.',
Av='Avyl:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.',
Ay='Ayannar:BAAANQADCgMIAwAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECgcICgABAAAAAA==.Azriella:BAAANQAECgcIDAAAAA==.Azuren:BAABNQAECn8qAAMGAAgKVw5oBQA2AQAGAAgKVw5oBQA2AQAHAAEKIAiiDwAjAAAAAA==.',
Ba='Bacon:BAABNQAECn80AAIIAAoKcCDMCQCqAQAIAAoKcCDMCQCqAQAAAA==.Bamboozled:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.Bankai:BAABNQAECn8qAAIJAAkKZSO/BABFAwAJAAkKZSO/BABFAwAAAA==.',
Be='Beardedtroll:BAABNQAECn8UAAIKAAkKRR5JDQAaAwAKAAkKRR5JDQAaAwAAAA==.Beefstrasz:BAACNQAFFH8PAAILAAQKTAVpDAD5AAALAAQKTAVpDAD5AAA1AAQKfy4AAgsACgr4Ek9TACkCAAsACgr4Ek9TACkCAAAA.Beyla:BAABNQAECn8WAAIMAAoKBgfV3gBdAQAMAAoKBgfV3gBdAQAAAA==.',
Bh='Bhalecgos:BAAANQADCgYIEAAAAA==.',
Bi='Bishamon:BAAANQAECgIIBgAAAA==.',
Bl='Blank:BAAANQAECgMIAwAAAA==.Bleau:BAAANQAECgYIDQAAAA==.Blethings:BAAANQADCgYIBgABNQAECggIDQABAAAAAA==.Bloodhornbob:BAAANQADCgUIDgAAAA==.Bloodimary:BAAANQADCgIIAgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodráyne:BAAANQADCgMIAwAAAA==.Bloodymary:BAABNQAECn8rAAINAAkK6RCgSwDIAQANAAkK6RCgSwDIAQAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAABNQAECn8qAAIOAAkKgBKoEQDaAQAOAAkKgBKoEQDaAQAAAA==.Bláze:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.Blôodräge:BAAANQAECgQIBAAAAA==.',
Bo='Bomm:BAAANQAECgEIAQAAAA==.Boolzeye:BAAANQABCgQICAAAAA==.Bouncy:BAAANQAECgIIAgAAAA==.Bowl:BAACNQAFFH8PAAIPAAQK3BxlAgDmAAAPAAQK3BxlAgDmAAA1AAQKfzIAAg8ACgryIqIIABMDAA8ACgryIqIIABMDAAAA.',
Br='Branchling:BAAANQAECgYIBgABNQAFFAcIFwAOAEQSAA==.Breaklimit:BAAANQADCggIDQAAAA==.',
Bu='Butterkip:BAACNQAFFH8TAAIQAAYKKgw1AgA7AQAQAAYKKgw1AgA7AQA1AAQKfyEAAhAACgpVGR8YAJMCABAACgpVGR8YAJMCAAAA.',
Ce='Cellan:BAAANQADCgYIEwAAAA==.',
Ch='Chewdawgg:BAAANQAECgYIBgAAAA==.Chewdogg:BAAANQADCgQIBAAAAA==.Cheww:BAABNQAECn8mAAMLAAoKsBZ/EQDqAQALAAkK/RZ/EQDqAQAQAAIKaAx4dQA7AAAAAA==.Chicknburger:BAAANQAECgEIAQAAAA==.Chlorofõrm:BAAANQAECgcIEAAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Choopamelo:BAAANQADCgEIAQAAAA==.Chopahoe:BAABNQAECn8nAAIRAAkKix6wBwCUAQARAAkKix6wBwCUAQAAAA==.Chudlock:BAAANQADCggIDwABNQAECgoKPQALALAkAA==.Chumpcooker:BAAANQADCgYICAAAAA==.',
Cl='Clamius:BAACNQAFFH8QAAMSAAUK/CIYBQDAAAAOAAQK0Ba2NQDuAAASAAIK7iMYBQDAAAA1AAQKfy0AAw4ACgp0I9YiAFEDAA4ACgpYItYiAFEDABIAAwrPJB8eAPwAAAAA.Cliff:BAABNQAECn8nAAITAAkKAiXgDQBSAwATAAkKAiXgDQBSAwAAAA==.',
Co='Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAABNQAECn8pAAMTAAoKzSShBACkAwATAAoKzSShBACkAwAUAAgKnBwXLwC/AgAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cortex:BAAANQADCgIIAgAAAA==.Cosmic:BAAANQADCgYIBgAAAA==.Cotopla:BAABNQAECn8XAAIOAAcK0A9E9QChAQAOAAcK0A9E9QChAQAAAA==.',
Cr='Crimsondream:BAABNQAECn8YAAMVAAcKdArKOQAeAQAVAAcKdArKOQAeAQAWAAEKAAAAfgAvAAAAAA==.',
Da='Daemea:BAAANQAECgIIAgAAAA==.Dagov:BAAANQAECgIIAgAAAA==.Darkart:BAAANQADCgYICgAAAA==.Darkshivers:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.Darkswarm:BAAANQAECgIIAgAAAA==.',
De='Deathlentlez:BAABNQAECn8lAAIXAAoK9BcODAB2AgAXAAoK9BcODAB2AgAAAA==.Decaylentlez:BAAANQAECgEIAQABNQAECgoKJQAXAPQXAA==.Deepséeded:BAAANQADCgEIAQABNQAECggIIQATAGMgAA==.Delphyne:BAABNQAECn8YAAIGAAkKTwWABgAYAQAGAAkKTwWABgAYAQAAAA==.Demonhunter:BAAANQAECgQICAAAAA==.Demonià:BAAANQAECgYICwAAAA==.',
Di='Diamondsword:BAAANQAECggICQAAAA==.Dinkleberg:BAAANQABCgUIBgAAAA==.',
Dj='Djazz:BAAANQAECgIIAQAAAA==.',
Dr='Drewsan:BAAANQAFFAEIAQAAAA==.Drowsee:BAAANQAECgYICAAAAA==.',
Du='Dulcinea:BAAANQAECgQICwAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
['Dú']='Dúncan:BAAANQADCggIDwAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAABNQAECn8rAAMIAAoK1hmGBAAhAgAIAAoKDRiGBAAhAgAYAAcKZh11CwAYAgAAAA==.',
Ei='Eirinny:BAAANQADCggIDgAAAA==.',
El='Elindez:BAAANQAECgcIDgAAAA==.Elyviel:BAAANQAECgcICgAAAA==.',
En='Encantado:BAAANQAECgEIAQAAAA==.End:BAAANQADCggICAAAAA==.',
Eo='Eowen:BAABNQAECn8kAAIDAAkKKQ28FwCZAQADAAkKKQ28FwCZAQAAAA==.',
Ep='Epitaph:BAAANQADCgYICwAAAA==.',
Ez='Ezmee:BAAANQAECgEIAQAAAA==.',
Fa='Faelicia:BAAANQADCgYIFwAAAA==.Falandoria:BAAANQAECgIIAgAAAA==.Fastnfurious:BAAANQAECgUIBgABNQAECgkJKwANAOkQAA==.',
Fr='Frostdruid:BAAANQADCgEIAQAAAA==.Frowmae:BAAANQAECgUIBwAAAA==.',
Fu='Fundip:BAAANQAECgYIDwAAAA==.',
Fy='Fythra:BAAANQAECgIIBQAAAA==.Fythri:BAAANQAECgEIAgABNQAECgIIBQABAAAAAA==.',
['Fù']='Fùrìeüx:BAAANQAECgEIAQAAAA==.',
Ga='Gart:BAAANQADCgcIBwAAAA==.Gawdsmackk:BAAANQAECgQIBAABNQAECgQICwABAAAAAA==.',
Ge='Geolock:BAAANQAECgQICAAAAA==.',
Gi='Gibbii:BAAANQAECgQIBAABNQAECgoKLAAZALoWAA==.Gibdergen:BAAANQADCgYIAwABNQAECgoKLAAZALoWAA==.Gibhasarms:BAAANQADCgYIBgABNQAECgoKLAAZALoWAA==.Giblock:BAABNQAECn8sAAMZAAoKuhbZAwCvAgAZAAoKuhbZAwCvAgAWAAEKUwlOFwAwAAAAAA==.Ginju:BAABNQAECn8fAAIUAAgK5RpCRABlAgAUAAgK5RpCRABlAgAAAA==.',
Gl='Glamour:BAAANQADCgYIBgABNQAECgYIDwABAAAAAA==.',
Go='Golomojek:BAAANQADCgYICgAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAABNQAECn8mAAIaAAkKsSL2BAA2AwAaAAkKsSL2BAA2AwAAAA==.Grawfern:BAABNQAECn8uAAMbAAoKASPzAQBXAgAbAAoKASPzAQBXAgAcAAYK5QiSawAdAQAAAA==.Graziella:BAAANQADCgYICQABNQAECgYIDAABAAAAAA==.',
Gu='Guldave:BAAANQAECgMIAwAAAA==.Guthrie:BAAANQAECgcICwAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAABNQAECn8hAAITAAoKLRbuHwBpAQATAAoKLRbuHwBpAQAAAA==.Harden:BAAANQADCgEIAQAAAA==.Hawktwua:BAAANQADCgQIBAABNQAECgUIEAABAAAAAA==.',
He='Healforbeer:BAAANQAECgUIBQAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAABNQAECn8nAAIQAAgKCxyFFwCbAgAQAAgKCxyFFwCbAgAAAA==.Hext:BAAANQADCgQIBAABNQAECgkJMgADAEUTAA==.',
Ho='Holygral:BAAANQABCggIFAABNQAECgkJJgAaALEiAA==.Holymun:BAAANQAECgQIBQAAAA==.Holyox:BAABNQAECn8zAAIMAAoKhgYMYwD/AAAMAAoKhgYMYwD/AAAAAA==.Hotcheeto:BAAANQAECgIIAwAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.Hturtledk:BAAANQAECggIBQAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.',
['Hü']='Hüntress:BAAANQAECgcIEAAAAA==.',
Ig='Ignuskore:BAAANQAECgEJAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECgkJFAAKAEUeAA==.Imgibby:BAAANQAECgUIDQABNQAECgoKLAAZALoWAA==.',
In='Inexorable:BAACNQAFFH8JAAIMAAIKOx0JDwCRAAAMAAIKOx0JDwCRAAA1AAQKfyoAAgwACAqPIzsQAPkBAAwACAqPIzsQAPkBAAAA.Inssaane:BAAANQADCggIDgAAAA==.Interesting:BAAANQADCgYIBgAAAA==.',
Io='Iolegnaro:BAABNQAECn8WAAIOAAcKMyS+cgCYAgAOAAcKMyS+cgCYAgABNQAFFAYIEwAUAFIjAA==.',
Ir='Irakwa:BAAANQAECgEIAQAAAA==.Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAACNQAFFH8cAAIRAAcK4CDcAgBNAgARAAcK4CDcAgBNAgA1AAQKfzQAAhEACgrYI+cDAJcDABEACgrYI+cDAJcDAAAA.',
Iz='Izry:BAABNQAECn8ZAAMEAAkKORCoIAAiAQAEAAkKORCoIAAiAQAdAAQKjQ0YoQC5AAAAAA==.Izánámi:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.',
Ja='Jaason:BAABNQAECn8rAAMEAAkKpxglCgC6AQAEAAkKdBglCgC6AQANAAYKuxIJbwA5AQAAAA==.Jalen:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQAECgUIBwABNQAECgUIEAABAAAAAA==.',
Jh='Jhora:BAAANQAECgMIBwAAAA==.Jhunts:BAAANQAECgYICwAAAA==.',
Ji='Jinfizz:BAAANQAECgIIAgAAAA==.Jinfuse:BAABNQAECn8kAAMOAAkKnhcFNgBSAQAOAAkKmhYFNgBSAQASAAEKDBw9OwBSAAAAAA==.',
Jo='Jormungandr:BAAANQADCgIIAgAAAA==.',
Jp='Jpdh:BAABNQAECn8vAAQIAAoKKiH4EAAYAwAIAAoK3R34EAAYAwACAAkKJhpNJwAKAgAYAAQKCyJ4EgCHAQAAAA==.Jpdumb:BAAANQAECgUIBQABNQAECgoKLwAIACohAA==.',
Ju='Juddory:BAAANQAECgUIDwAAAA==.Junksvil:BAAANQAECgUIEAAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Ke='Kealthara:BAAANQAECgQIBQAAAA==.',
Kh='Khalyon:BAABNQAECn8wAAIOAAoKtBeKbQCjAgAOAAoKtBeKbQCjAgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.Kilowatts:BAAANQABCgEIAQAAAA==.',
Ko='Koa:BAAANQAECgEIAQAAAA==.Koppel:BAAANQAECgUIDAABNQAECgUIDwABAAAAAA==.Korinth:BAECNQAFFH8LAAIMAAQKaAvZCQDMAAAMAAQKaAvZCQDMAAA1AAQKfy4AAwwACgqqGylRAKICAAwACgqqGylRAKICAA8AAgpnH4tWAIcAAAAA.',
Kr='Kriaalis:BAAANQAECgIIAgAAAA==.',
Ku='Kunitsu:BAAANQAECgQICwAAAA==.',
Ky='Kyra:BAAANQAECgQIBAAAAA==.Kyril:BAABNQAECn8qAAIMAAkK3yPEGQBdAwAMAAkK3yPEGQBdAwAAAA==.',
['Kæ']='Kælas:BAAANQADCgUIBQAAAA==.',
La='Lagabriela:BAABNQAECn8qAAINAAkKDgmDGwAVAQANAAkKDgmDGwAVAQAAAA==.Lazuli:BAAANQADCgQIBAABNQAECgoKNAAIAHAgAA==.',
Le='Legault:BAABNQAECn8jAAIeAAkKyBOvCAAOAgAeAAkKyBOvCAAOAgAAAA==.Legionofboom:BAAANQAECgIIAgAAAA==.Lemanruss:BAAANQADCgQIBAAAAA==.Lethfel:BAAANQAECggIDQAAAA==.',
Li='Lilgoukii:BAAANQAECgEIAQAAAA==.Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQAECgIIAgAAAA==.Lionfury:BAAANQAECgQICQABNQAFFAMIBgAMAM0FAA==.Lionguard:BAACNQAFFH8GAAIMAAMKzQVRDQCdAAAMAAMKzQVRDQCdAAA1AAQKfyMAAgwACgrdFMWGABoCAAwACgrdFMWGABoCAAAA.Livie:BAAANQAECgQICgAAAA==.Lizzard:BAAANQADCggICAABNQAFFAMIBQAfANEUAA==.',
Lo='Loca:BAABNQAECn8iAAITAAoKZQfIRADbAAATAAoKZQfIRADbAAAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loraddesmos:BAABNQAECn8lAAMWAAoKMgpDAwAYAQAWAAkK5wpDAwAYAQAVAAIKcwUFuwA0AAAAAA==.Loáth:BAAANQADCgcIBwABNQAECgYIFQAbAOkRAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.Lullaby:BAAANQAECgUIBQAAAA==.',
Ly='Lycanthrope:BAAANQAECgEIAQAAAA==.Lyship:BAAANQAECgIIAgAAAA==.',
Ma='Maeg:BAAANQAECgYICgABNQAECgkJFAAKAEUeAA==.Mahll:BAABNQAECn8hAAIVAAoKjBu4CQAMAgAVAAoKjBu4CQAMAgAAAA==.Maidenchina:BAAANQAECgMIAwAAAA==.Maleveck:BAAANQAECgYIBgAAAA==.Marcato:BAAANQADCgQIBQABNQAECgYIDAABAAAAAA==.Marcdofu:BAAANQAECgEIAgAAAA==.Mardista:BAAANQADCgYIBgAAAA==.Mataquay:BAAANQAECgEIAQAAAA==.',
Mc='Mctanker:BAAANQAECgYICgAAAA==.',
Me='Meascii:BAABNQAECn8rAAMLAAoKyR7OCwBkAwALAAoKyR7OCwBkAwAgAAgKvg7iCQCxAQAAAA==.Megavolt:BAAANQADCggICAABNQAFFAcIHAARAOAgAA==.Megs:BAAANQADCggJEwAAAA==.Memebeams:BAAANQAECgQIBwAAAA==.Merc:BAACNQAFFH8KAAIRAAUKpAsgCwAGAQARAAUKpAsgCwAGAQA1AAQKfygAAhEACgqNHx8PAPECABEACgqNHx8PAPECAAAA.',
Mi='Miluo:BAAANQAECgMIBQABNQAECgkJHwAfADsfAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBAAAAA==.Mirefighter:BAAANQAECgMIAwABNQAFFAQIDwAaAIgWAA==.Mirespike:BAACNQAFFH8PAAMaAAQKiBavAQBWAQAaAAQKiBavAQBWAQAcAAEKxQLEEgA/AAA1AAQKfyoAAxoACgrYHhAFADMDABoACgrYHhAFADMDABwAAQoAANC0AC4AAAAA.Mistbrew:BAAANQAECgYICwABNQAECggIEgABAAAAAA==.Miushi:BAEANQABCgIIAgABNQAFFAQICwAMAGgLAA==.',
Mo='Modin:BAAANQAECgYIDQABNQAECggIIwADAC4UAA==.Mommacougar:BAAANQADCgIIAgAAAA==.Moon:BAAANQADCgUICgABNQADCgYIDwABAAAAAA==.Morawynd:BAAANQAECgQIBgAAAA==.Morlis:BAAANQAECgEIAgAAAA==.Morlock:BAABNQAECn8mAAIVAAkKDQoETADvAAAVAAkKDQoETADvAAAAAA==.Morningstahr:BAABNQAECn8hAAIOAAoKxBXxigBpAgAOAAoKxBXxigBpAgAAAA==.Morphìc:BAAANQAECgUIBgAAAA==.',
Mu='Munion:BAAANQAECgQJBAABNQAECgQIBQABAAAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Mô']='Môrningstar:BAAANQADCgUIBQAAAA==.',
Na='Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQAECgIIAgAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyfused:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyvoked:BAAANQAECgUIBAABNQAECgUIDAABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEIAQAAAA==.',
Ni='Nickayla:BAAANQAECgYICwAAAA==.Nikkaya:BAAANQADCgYJBgABNQAECgUIEAABAAAAAA==.Nimblecow:BAAANQADCgEIAQAAAA==.',
No='Noobacleese:BAABNQAECn8oAAIMAAoKqhPlNQBfAQAMAAoKqhPlNQBfAQAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.Novarak:BAAANQADCgMIAwAAAA==.Noyn:BAAANQAECgEIAQABNQAECgkJHwAfADsfAA==.',
Ny='Nyghtrider:BAAANQAECgUIEAAAAA==.Nymëra:BAABNQAECn8XAAITAAgKgwwrmABKAQATAAgKgwwrmABKAQAAAA==.Nyneeve:BAABNQAECn8dAAIQAAgK3AtFDgAkAQAQAAgK3AtFDgAkAQAAAA==.',
Od='Odinshunter:BAAANQADCgIIAgAAAA==.Odst:BAAANQAECgIIAQABNQAECgcIDwABAAAAAA==.',
Ol='Olgrin:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
On='Onepunch:BAAANQADCgcIBwAAAA==.Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQAECgEIAgAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBQAAAA==.Pandaloons:BAAANQAECgEIAQAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQAECgYIDAAAAA==.',
Pb='Pbób:BAAANQAECggICwAAAA==.',
Pe='Percocetpete:BAABNQAECn8mAAMLAAoKFR7gEgA0AwALAAkKYiHgEgA0AwAQAAgKRgcKNQB7AQAAAA==.Peregrine:BAAANQAECgEIAQAAAA==.',
Ph='Phaet:BAACNQAFFH8NAAMVAAQKjRk7DAC0AAAVAAMKwBw7DAC0AAAWAAEKJxONBwBYAAA1AAQKfywAAxUACgpuIS8VAKEBABUACQrLIS8VAKEBABYABAoHFRgyAP0AAAAA.Phaux:BAAANQAECgEIAgAAAA==.',
Pi='Piper:BAAANQAECgYICgAAAA==.',
Pl='Plâgue:BAABNQAECn8tAAIdAAoKOCBDHgDWAgAdAAoKOCBDHgDWAgAAAA==.',
Pr='Prot:BAAANQADCgUIBQAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECggIJQAaAOcmAA==.Puntthegnome:BAAANQADCgEIAQABNQAFFAcIFwAOAEQSAA==.',
Ra='Rainforest:BAAANQAECgUIEAAAAA==.Raktoth:BAAANQADCggICAAAAA==.Ramden:BAABNQAECn8rAAIMAAoKSAeadgDaAAAMAAoKSAeadgDaAAAAAA==.Rampant:BAAANQAECgcIDwAAAA==.Rampscii:BAAANQAECgUICwABNQAECgcIDwABAAAAAA==.Randolier:BAABNQAECn8nAAIfAAkKSB8CKgDwAgAfAAkKSB8CKgDwAgAAAA==.Ratherton:BAACNQAFFH8XAAMOAAcKRBIVEAD2AQAOAAYKIhYVEAD2AQASAAEKywL2BwBTAAA1AAQKfzMAAg4ACgozIQsdAGMDAA4ACgozIQsdAGMDAAAA.Rathtard:BAABNQAECn8dAAIfAAoKihiVQQCmAgAfAAoKihiVQQCmAgABNQAFFAcIFwAOAEQSAA==.Rauzer:BAAANQABCgIIAgAAAA==.Razz:BAAANQAECgEIAQAAAA==.',
Re='Renuwu:BAABNQAECn85AAILAAkKwREEIwB1AQALAAkKwREEIwB1AQAAAA==.Resoluteone:BAABNQAECn8tAAINAAoKpAdtFwAtAQANAAoKpAdtFwAtAQAAAA==.Retnu:BAAANQADCgQICwAAAA==.Revelations:BAAANQAECgMIAwABNQAECgoKKQATAM0kAA==.Revytwohand:BAACNQAFFH8PAAIRAAQK0Bk5BADZAAARAAQK0Bk5BADZAAA1AAQKfzEAAhEACgrPH08RANYCABEACgrPH08RANYCAAAA.',
Rh='Rhok:BAAANQAECgIIAQAAAA==.',
Ro='Robonome:BAAANQADCgUIBQAAAA==.',
Ru='Rumii:BAAANQAECgQIBQAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
['Rö']='Rödrïck:BAAANQAECgUICQABNQAECgoKMQAVAD4bAA==.',
Sa='Sabeladys:BAABNQAECn8VAAIMAAgKVwtrhgDDAAAMAAgKVwtrhgDDAAAAAA==.Saifir:BAABNQAECn8nAAMUAAgKHxcIvwAUAQAUAAUK3hAIvwAUAQATAAgKogiISgDMAAAAAA==.Sallyd:BAAANQAECgEIAQAAAA==.Sardmagia:BAAANQAECgIIAgABNQAECgUJDAABAAAAAA==.Sardmongo:BAAANQAECgEIAQAAAA==.Sarduccini:BAAANQAECgUJDAAAAA==.',
Sh='Shadowpriest:BAAANQABCgIIAgAAAA==.Shamwowzer:BAAANQADCgQIBAAAAA==.Shelisaria:BAAANQAECgUIBAAAAA==.Shiftken:BAAANQADCgMIAwAAAA==.Shoktherapy:BAABNQAECn8hAAMTAAgKYyCIAwDZAgATAAgKYyCIAwDZAgAUAAEKAAAHOAEyAAAAAA==.',
Si='Silvalus:BAAANQAECgIIAgAAAA==.Silvertide:BAABNQAECn8qAAMUAAkKYBE0CwC6AQAUAAkKYBE0CwC6AQATAAcK3w6IiwBtAQAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skonka:BAAANQADCggICAAAAA==.Skyeforce:BAAANQADCggIDgAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
So='Soi:BAABNQAECn8fAAMfAAkKOx8qLwDfAgAfAAkKOx8qLwDfAgAhAAIKJA0BdABpAAAAAA==.Solas:BAAANQAECgQIBAAAAA==.Solvent:BAAANQADCggICwAAAA==.Sondaar:BAAANQABCgcIDQAAAA==.Sonoforak:BAAANQAECgMJAwAAAA==.',
Sp='Sped:BAABNQAECn8qAAIXAAgK7iEGAgAFAgAXAAgK7iEGAgAFAgAAAA==.',
St='Staraleena:BAAANQAECgQIBAAAAA==.Stiffyhaze:BAAANQAECgQIBAAAAA==.Stillwët:BAAANQABCggICwAAAA==.Stingyr:BAAANQAECgcIEAAAAA==.Stormslight:BAAANQAECgIIAQAAAA==.Stormsteel:BAAANQAECgMIAwAAAA==.Stossel:BAAANQAECgUIDwAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Ta='Tab:BAAANQAECgIIAQAAAA==.Tabio:BAAANQADCgYIBwAAAA==.Taboptics:BAAANQAECgQIBQAAAA==.Talas:BAABNQAECn8nAAIPAAkKQxbNGwAPAgAPAAkKQxbNGwAPAgAAAA==.Tamarack:BAAANQAECgYIBwAAAA==.Tanksabunch:BAABNQAECn8XAAIiAAoKhQ0crQCsAQAiAAoKhQ0crQCsAQABNQAFFAcIGwAhACkkAA==.',
Te='Tehmay:BAAANQADCgIIAgAAAA==.Tenssid:BAAANQADCggIGAAAAA==.Terrormisu:BAAANQAECgcICQAAAA==.',
Th='Thorclap:BAAANQAECgEJAQAAAA==.Thundertaker:BAAANQADCgYICgAAAA==.',
Ti='Tim:BAAANQADCggJCgABNQAECgoKJwAJAIAdAA==.Tiniashio:BAAANQAECgQIBAABNQAECggIGAAVAHQKAA==.',
To='Tooru:BAACNQAFFH8FAAIfAAMK0RTqBwDqAAAfAAMK0RTqBwDqAAA1AAQKfzIAAx8ACgpWIUgTAFIDAB8ACgpWIUgTAFIDACEACAqoD341AKIBAAAA.',
Tr='Traest:BAAANQAECgEIAwAAAA==.Treebeef:BAAANQAECgMIAwAAAA==.Triena:BAAANQADCggJCAAAAA==.Trimas:BAAANQAECgEIAQAAAA==.',
Tt='Tt:BAAANQAECggICQAAAA==.',
Tw='Twinkles:BAABNQAECn8jAAMDAAgKLhQ/WwAHAgADAAgKLhQ/WwAHAgAMAAEKzwcMtwEsAAAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ty='Typicaldrood:BAAANQAECgMIAwAAAA==.Typicalmonk:BAAANQADCgQIBAAAAA==.',
Ul='Ulysius:BAABNQAECn8eAAIMAAkKHhKkmADyAQAMAAkKHhKkmADyAQAAAA==.',
Va='Valkisek:BAABNQAECn8fAAISAAoKuhZnBwB6AgASAAoKuhZnBwB6AgAAAA==.Vallarfax:BAABNQAECn8kAAIfAAkKdhlmUAB+AgAfAAkKdhlmUAB+AgAAAA==.Vandro:BAABNQAECn8yAAIDAAkKRRMVGACXAQADAAkKRRMVGACXAQAAAA==.Varea:BAAANQAECgYICwABNQAECgkJMwAOAKQXAA==.Vashdk:BAACNQAFFH8PAAINAAQKxBwbEABUAQANAAQKxBwbEABUAQA1AAQKfy4AAg0ACgo8JIgIAHYDAA0ACgo8JIgIAHYDAAAA.',
Ve='Velcyn:BAAANQAFFAIIBAAAAA==.Veloranas:BAABNQAECn8zAAMOAAkKpBd1KgBxAQAOAAkKlxd1KgBxAQASAAMK3xGTKwCeAAAAAA==.Venjince:BAAANQADCgYIBgAAAA==.Venôm:BAAANQADCgQIBAAAAA==.Vespyr:BAAANQAECgYIDgABNQAECgcIEAABAAAAAA==.Vewdoo:BAABNQAECn8uAAIUAAoK4iKSAQDpAgAUAAoK4iKSAQDpAgAAAA==.Vexiara:BAAANQADCgcIDwABNQAECgcICgABAAAAAA==.',
Vi='Vizimir:BAAANQAECgYICwAAAA==.',
Vy='Vynstabbin:BAAANQAECgUJCgABNQAECgcIDAABAAAAAA==.',
Wa='Waiwai:BAAANQADCgcIBwAAAA==.Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAAANQAECgQIDAABNQAECgcIDwABAAAAAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wh='Whiskeybear:BAAANQADCgYICAAAAA==.',
Wi='Willowes:BAAANQADCgYIBgAAAA==.Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wivvy:BAAANQAECggIDgAAAA==.Wizkerbizkit:BAABNQAECn8fAAMhAAcK0gdoHgCjAAAhAAYKAQloHgCjAAAfAAEKEwPb2QAgAAAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wooshira:BAAANQAECgEIAQAAAA==.',
Wy='Wyrmheal:BAABNQAECn8yAAIQAAoKtyBWAwDmAQAQAAoKtyBWAwDmAQAAAA==.Wyvvie:BAABNQAECn8ZAAIjAAkKkRPxFAAsAgAjAAkKkRPxFAAsAgAAAA==.',
Ya='Yamihime:BAABNQAECn8mAAMIAAoKhRe0IQCOAgAIAAoKhRe0IQCOAgACAAEKAAA2bgAxAAAAAA==.Yatiri:BAAANQAECgcICQAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.Zambas:BAAANQAECgMIAwAAAA==.',
Ze='Zeaket:BAACNQAFFH8fAAIkAAYK0SA5AABRAgAkAAYK0SA5AABRAgA1AAQKfzEAAiQACgoNJccAAJgDACQACgoNJccAAJgDAAAA.Zephyr:BAAANQADCgcIJgABNQAECgcIEAABAAAAAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQAECgQIBAABNQAECgkJHwAfADsfAA==.',
Zi='Zinbad:BAAANQAECgEIAQAAAA==.',
Zo='Zorcan:BAAANQAECgUICgAAAA==.',
Zu='Zugzugz:BAAANQAECggICAAAAA==.Zulfilith:BAAANQAECgEIAQAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Än']='Äncïênt:BAAANQADCgcIBwAAAA==.',
['Ða']='Ðachee:BAABNQAECn8lAAILAAkKSSA3BADfAgALAAkKSSA3BADfAgAAAA==.',
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
