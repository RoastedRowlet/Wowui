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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Paladin-Holy','DeathKnight-Frost','Druid-Restoration','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','Shaman-Enhancement','Priest-Holy','DeathKnight-Blood','Mage-Arcane','Paladin-Protection','Priest-Shadow','Monk-Windwalker','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','DemonHunter-Vengeance','Warlock-Affliction','Druid-Feral','Druid-Guardian','Druid-Balance','Paladin-Retribution','Rogue-Outlaw','Warlock-Destruction','Warlock-Demonology','Priest-Discipline','Hunter-BeastMastery','DeathKnight-Unholy','Hunter-Marksmanship','Warrior-Arms','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aadrik:BAAANQADCggICAAAAA==.',
Ad='Adrenalin:BAAANQAECgUIDAAAAA==.Adversary:BAAANQADCgcICQAAAA==.',
Ae='Aennish:BAAANQABCgIIBgAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.Agross:BAAANQADCggIEAAAAA==.',
Ai='Airibeth:BAAANQAECgMIAgAAAA==.Aiyanna:BAAANQADCgYIDQABNQAECgUIEAABAAAAAA==.',
Al='Alric:BAABNQAECn8aAAICAAgKkRbvIwAkAgACAAgKkRbvIwAkAgAAAA==.Althalos:BAAANQABCgQIBgAAAA==.',
Ao='Aothanu:BAAANQADCgEIAQAAAA==.',
Ap='Aprit:BAAANQAECgUIBQAAAA==.',
Ar='Aracia:BAAANQADCgMIAwAAAA==.Ardhammer:BAAANQAECgQJBAAAAA==.Arragorn:BAABNQAECn8dAAIDAAkKjw6QYwDrAQADAAkKjw6QYwDrAQAAAA==.',
As='Asendra:BAAANQAECgQICAAAAA==.Astal:BAACNQAFFH8LAAIEAAQKxxYCCwAsAQAEAAQKxxYCCwAsAQA1AAQKfygAAgQACQrdIjQSAPkCAAQACQrdIjQSAPkCAAAA.',
At='Ate:BAABNQAECn8dAAIFAAgKpxQuJwDkAQAFAAgKpxQuJwDkAQAAAA==.',
Au='Aurathur:BAAANQAECgUIDAAAAA==.',
Av='Avyl:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.',
Ay='Ayannar:BAAANQADCgMIAwAAAA==.',
Az='Azalenne:BAAANQAECgIIAgABNQAECgcICgABAAAAAA==.Azriella:BAAANQAECgMIBQAAAA==.Azuren:BAABNQAECn8iAAMGAAgKkQ1MFAAGAgAGAAgKkQ1MFAAGAgAHAAEKlwNVKAAcAAAAAA==.',
Ba='Bacon:BAABNQAECn8uAAIIAAgK2R9hGQDMAgAIAAgK2R9hGQDMAgAAAA==.Bamboozled:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Bankai:BAABNQAECn8nAAIJAAgKQCWjBABHAwAJAAgKQCWjBABHAwAAAA==.',
Be='Beardedtroll:BAAANQAECggIDwAAAA==.Beefstrasz:BAACNQAFFH8LAAIKAAQKiAQJHAABAQAKAAQKiAQJHAABAQA1AAQKfy0AAgoACQqPEyBSACkCAAoACQqPEyBSACkCAAAA.Beyla:BAAANQAECggIEQAAAA==.',
Bh='Bhalecgos:BAAANQADCgYIEAAAAA==.',
Bi='Bishamon:BAAANQAECgIIBQAAAA==.',
Bl='Blank:BAAANQAECgMIAwAAAA==.Bleau:BAAANQAECgYIDQAAAA==.Blethings:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Bloodhornbob:BAAANQADCgUIDgAAAA==.Bloodimary:BAAANQADCgIIAgAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodráyne:BAAANQADCgMIAwAAAA==.Bloodymary:BAABNQAECn8nAAILAAgKFRPgSgDIAQALAAgKFRPgSgDIAQAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAABNQAECn8iAAIMAAgKBxPHtQAWAgAMAAgKBxPHtQAWAgAAAA==.',
Bo='Boolzeye:BAAANQABCgQICAAAAA==.Bouncy:BAAANQAECgIIAgAAAA==.Bowl:BAACNQAFFH8LAAINAAQK3ByZBQBHAQANAAQK3ByZBQBHAQA1AAQKfy4AAg0ACQqUIogIABQDAA0ACQqUIogIABQDAAAA.',
Br='Branchling:BAAANQAECgYIBgABNQAFFAYIFQAMACIWAA==.Breaklimit:BAAANQADCggIDQAAAA==.',
Bu='Butterkip:BAACNQAFFH8OAAIOAAUKpwyKCQBkAQAOAAUKpwyKCQBkAQA1AAQKfyAAAg4ACQrjGe0XAJMCAA4ACQrjGe0XAJMCAAAA.',
Ce='Cellan:BAAANQADCgYIEwAAAA==.',
Ch='Chewdawgg:BAAANQAECgYIBgAAAA==.Chewdogg:BAAANQADCgQIBAAAAA==.Cheww:BAABNQAECn8dAAMKAAkKrhF2WAAVAgAKAAkKrhF2WAAVAgAOAAEKAADkcwA7AAAAAA==.Chicknburger:BAAANQAECgEIAQAAAA==.Chlorofõrm:BAAANQAECgcIDgAAAA==.Chokonit:BAAANQAECgMIBAAAAA==.Choopamelo:BAAANQADCgEIAQAAAA==.Chopahoe:BAABNQAECn8hAAIPAAgKYSAmEgDJAgAPAAgKYSAmEgDJAgAAAA==.Chudlock:BAAANQADCggJDwABNQAECgkJNgAKAMshAA==.Chumpcooker:BAAANQADCgYICAAAAA==.',
Cl='Clamius:BAACNQAFFH8PAAMQAAQKTiTsBADBAAAMAAMKtRKVNADtAAAQAAIK7iPsBADBAAA1AAQKfyoAAwwACQp2JbohAFQDAAwACQoyJLohAFQDABAAAwrPJLsdAPwAAAAA.Cliff:BAABNQAECn8hAAIRAAgKdiWjDQBSAwARAAgKdiWjDQBSAwAAAA==.',
Co='Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAABNQAECn8oAAMRAAkKwSR8BAClAwARAAkKwSR8BAClAwASAAgKnBxbLgDAAgAAAA==.Coombrain:BAAANQADCgIIAwAAAA==.Cortex:BAAANQADCgIIAgAAAA==.Cosmic:BAAANQADCgYIBgAAAA==.Cotopla:BAABNQAECn8XAAIMAAcK0A/v8gCiAQAMAAcK0A/v8gCiAQAAAA==.',
Cr='Crimsondream:BAAANQAECgUIDAAAAA==.',
Da='Daemea:BAAANQAECgIIAgAAAA==.Dagov:BAAANQAECgIIAgAAAA==.Darkart:BAAANQADCgYICgAAAA==.Darkshivers:BAAANQADCgcIBwABNQAECgEIAgABAAAAAA==.',
De='Deathlentlez:BAABNQAECn8eAAITAAkKphjqCwB3AgATAAkKphjqCwB3AgAAAA==.Decaylentlez:BAAANQAECgEIAQABNQAECgkJHgATAKYYAA==.Deepséeded:BAAANQADCgEIAQAAAA==.Delphyne:BAAANQAECgYIDQAAAA==.Demonhunter:BAAANQAECgQICAAAAA==.Demonià:BAAANQAECgUIBwAAAA==.',
Di='Dinkleberg:BAAANQABCgUIBgAAAA==.Disçiple:BAAANQADCggIEgAAAA==.',
Dj='Djazz:BAAANQADCgMIAwAAAA==.',
Dr='Drewsan:BAAANQAECgYICAAAAA==.Drowsee:BAAANQAECgUIBwAAAA==.',
Du='Dulcinea:BAAANQAECgQICAAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
['Dú']='Dúncan:BAAANQADCggICAAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAABNQAECn8gAAMIAAkKahzTGADRAgAIAAkKFxrTGADRAgAUAAcKZh1QCwAYAgAAAA==.',
Ei='Eirinny:BAAANQADCggIDgAAAA==.',
El='Elindez:BAAANQAECgYIDQAAAA==.Elyviel:BAAANQAECgcICgAAAA==.',
En='Encantado:BAAANQAECgEIAQAAAA==.End:BAAANQADCggICAAAAA==.',
Eo='Eowen:BAABNQAECn8cAAIDAAcKgwy0iAB+AQADAAcKgwy0iAB+AQAAAA==.',
Ep='Epitaph:BAAANQADCgYICwAAAA==.',
Ez='Ezmee:BAAANQADCggILgAAAA==.',
Fa='Faelicia:BAAANQADCgYIEQAAAA==.Falandoria:BAAANQAECgIIAgAAAA==.Fastnfurious:BAAANQAECgUIBgABNQAECggIJwALABUTAA==.',
Fr='Frostdruid:BAAANQADCgEIAQAAAA==.Frowmae:BAAANQAECgUIBwAAAA==.',
Fu='Fundip:BAAANQAECgUIDgAAAA==.',
Fy='Fythra:BAAANQAECgIIAgAAAA==.Fythri:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
['Fù']='Fùrìeüx:BAAANQAECgEIAQAAAA==.',
Ga='Gart:BAAANQADCgcIBwAAAA==.',
Ge='Geolock:BAAANQAECgIIAwAAAA==.',
Gi='Gibbii:BAAANQADCgUIBQABNQAECgkJJgAVAEoYAA==.Gibhasarms:BAAANQADCgYIBgABNQAECgkJJgAVAEoYAA==.Giblock:BAABNQAECn8mAAIVAAkKShiMBACPAgAVAAkKShiMBACPAgAAAA==.Ginju:BAABNQAECn8fAAISAAgK5RpCQwBlAgASAAgK5RpCQwBlAgAAAA==.',
Go='Golomojek:BAAANQADCgYICgAAAA==.Govs:BAAANQADCgMIAwAAAA==.',
Gr='Gralmerte:BAABNQAECn8iAAIWAAgKPyPVBAA3AwAWAAgKPyPVBAA3AwAAAA==.Grawfern:BAABNQAECn8mAAMXAAcKaiWZBwAHAwAXAAcKaiWZBwAHAwAYAAYK5QiNagAdAQAAAA==.Graziella:BAAANQADCgYICQABNQAECgYIDAABAAAAAA==.',
Gu='Guldave:BAAANQAECgMIAwAAAA==.Guthrie:BAAANQAECgUICQAAAA==.',
['Gø']='Gødøfwarz:BAAANQAECggICAAAAA==.',
Ha='Haether:BAABNQAECn8aAAIRAAgKOhgaRgBGAgARAAgKOhgaRgBGAgAAAA==.Harden:BAAANQADCgEIAQAAAA==.',
He='Healforbeer:BAAANQADCgQIBgAAAA==.Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAABNQAECn8nAAIOAAgKCxxRFwCbAgAOAAgKCxxRFwCbAgAAAA==.Hext:BAAANQADCgQIBAABNQAECggIKgADAGwTAA==.',
Ho='Holygral:BAAANQABCggIFAABNQAECggIIgAWAD8jAA==.Holymun:BAAANQAECgIIAgABNQAECgQJBAABAAAAAA==.Holyox:BAABNQAECn8pAAIZAAgKgwck1ABtAQAZAAgKgwck1ABtAQAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.Hturtledk:BAAANQAECggIBAAAAA==.',
Hy='Hyrri:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.',
['Hü']='Hüntress:BAAANQAECgYICgAAAA==.',
Ig='Ignuskore:BAAANQAECgEJAQAAAA==.',
Im='Imdatroll:BAAANQADCgMIAwABNQAECggIDwABAAAAAA==.Imgibby:BAAANQAECgQICAABNQAECgkJJgAVAEoYAA==.',
In='Inexorable:BAACNQAFFH8HAAIZAAIKOx30HwCfAAAZAAIKOx30HwCfAAA1AAQKfyUAAhkACAqPI/EoACADABkACAqPI/EoACADAAAA.Inssaane:BAAANQADCggIDgAAAA==.Interesting:BAAANQADCgYICgAAAA==.',
Io='Iolegnaro:BAABNQAECn8WAAIMAAcKMyS6cQCaAgAMAAcKMyS6cQCaAgABNQAFFAUIEgASAMwlAA==.',
Ir='Irakwa:BAAANQAECgEIAQAAAA==.Ironfel:BAAANQADCgQIBAAAAA==.',
It='Itches:BAACNQAFFH8aAAIPAAYK5yS+AgBNAgAPAAYK5yS+AgBNAgA1AAQKfzAAAg8ACQoyJs8DAJcDAA8ACQoyJs8DAJcDAAAA.',
Iz='Izry:BAAANQAECgcIEQAAAA==.Izánámi:BAAANQADCggICAABNQAECgcIDgABAAAAAA==.',
Ja='Jaason:BAABNQAECn8jAAMEAAgKQRqtJwBVAgAEAAgKmRmtJwBVAgALAAYKuxIdbgA5AQAAAA==.Jalen:BAAANQADCgYIBgAAAA==.Janvi:BAAANQADCgMIAwAAAA==.Jarico:BAAANQAECgUIBwABNQAECgUIEAABAAAAAA==.',
Jh='Jhora:BAAANQAECgMIBAAAAA==.Jhunts:BAAANQAECgYICwAAAA==.',
Ji='Jinfizz:BAAANQAECgIIAgAAAA==.Jinfuse:BAABNQAECn8eAAMMAAgK3xgPkgBbAgAMAAgKsBcPkgBbAgAQAAEKDBx0OgBSAAAAAA==.',
Jo='Jormungandr:BAAANQADCgIIAgAAAA==.',
Jp='Jpdh:BAABNQAECn8qAAQIAAkKmR+VEAAZAwAIAAkKuB2VEAAZAwACAAcKWhvTJgALAgAUAAQKCyIiEgCIAQAAAA==.Jpdumb:BAAANQAECgUIBQABNQAECgkJKgAIAJkfAA==.',
Ju='Juddory:BAAANQAECgQICgAAAA==.Junksvil:BAAANQAECgUIEAAAAA==.',
['Jø']='Jøhnwick:BAAANQADCgIIAgAAAA==.',
Ke='Kealthara:BAAANQAECgEIAQAAAA==.',
Kh='Khalyon:BAABNQAECn8sAAIMAAkKDhpmawCnAgAMAAkKDhpmawCnAgAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.Kilowatts:BAAANQABCgEIAQAAAA==.',
Ko='Koa:BAAANQAECgEIAQAAAA==.Koppel:BAAANQAECgUIBQAAAA==.Korinth:BAECNQAFFH8HAAIZAAMKaAvsGQDUAAAZAAMKaAvsGQDUAAA1AAQKfyoAAxkACQrHGs9PAKICABkACQrHGs9PAKICAA0AAgpnH4VVAIcAAAAA.',
Kr='Kriaalis:BAAANQADCgEIAQAAAA==.',
Ku='Kunitsu:BAAANQAECgQICwAAAA==.',
Ky='Kyra:BAAANQADCggIDgAAAA==.Kyril:BAABNQAECn8qAAIZAAkK3yMXGQBeAwAZAAkK3yMXGQBeAwAAAA==.',
['Kæ']='Kælas:BAAANQADCgUIBQAAAA==.',
La='Lagabriela:BAABNQAECn8iAAILAAcKHApHcAAwAQALAAcKHApHcAAwAQAAAA==.Lazuli:BAAANQADCgQIBAABNQAECggILgAIANkfAA==.',
Le='Legault:BAABNQAECn8fAAIaAAcKeRefCAAOAgAaAAcKeRefCAAOAgAAAA==.Legionofboom:BAAANQAECgEIAQAAAA==.Lemanruss:BAAANQADCgQIBAAAAA==.Lethfel:BAAANQAECgYIDAAAAA==.',
Li='Lilgoukii:BAAANQADCgQIBAAAAA==.Lillithfaust:BAAANQAECgEIAQAAAA==.Limbø:BAAANQAECgIIAgAAAA==.Lionfury:BAAANQAECgQICQABNQAECgkJHwAZAL4WAA==.Lionguard:BAABNQAECn8fAAIZAAkKvhaAhAAaAgAZAAkKvhaAhAAaAgAAAA==.Livie:BAAANQAECgQIBgAAAA==.',
Lo='Loca:BAABNQAECn8eAAIRAAkK7gSNiABxAQARAAkK7gSNiABxAQAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loraddesmos:BAABNQAECn8fAAMbAAkKkAdCGwCSAQAbAAgK4AdCGwCSAQAcAAEKrQWyUgEhAAAAAA==.Loáth:BAAANQADCgcIBwABNQAECgYIEAABAAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.',
Ly='Lyship:BAAANQAECgIIAgAAAA==.',
Ma='Maeg:BAAANQAECgYICgABNQAECggIDwABAAAAAA==.Mahll:BAAANQAECggIEgAAAA==.Maidenchina:BAAANQAECgMIAwAAAA==.Maleveck:BAAANQAECgYIBgAAAA==.Marcato:BAAANQADCgQIBQABNQAECgYIDAABAAAAAA==.Marcdofu:BAAANQAECgEIAQAAAA==.Mardista:BAAANQADCgYIBgAAAA==.',
Mc='Mctanker:BAAANQAECgEIAwAAAA==.',
Me='Meascii:BAABNQAECn8nAAMKAAkKySB/CwBlAwAKAAkKySB/CwBlAwAdAAgKvg7UCQCxAQAAAA==.Megavolt:BAAANQADCggICAABNQAFFAYIGgAPAOckAA==.Megs:BAAANQADCggJEwAAAA==.Memebeams:BAAANQAECgQIBQAAAA==.Merc:BAACNQAFFH8JAAIPAAQKrw3pCgAGAQAPAAQKrw3pCgAGAQA1AAQKfycAAg8ACQqSIOUOAPECAA8ACQqSIOUOAPECAAAA.',
Mi='Miluo:BAAANQAECgMIBQABNQAECggIHgAeAKUiAA==.Mindpuck:BAAANQADCgcIDAAAAA==.Mintchyp:BAAANQAECgQIBAAAAA==.Mirefighter:BAAANQAECgMIAwABNQAFFAQICwAWAIgWAA==.Mirespike:BAACNQAFFH8LAAIWAAQKiBahAQBWAQAWAAQKiBahAQBWAQA1AAQKfyYAAxYACQrWIeUEADUDABYACQrWIeUEADUDABgAAQoAAMuyAC4AAAAA.Missroxy:BAAANQADCgEIAQAAAA==.Mistbrew:BAAANQAECgYICwAAAA==.Miushi:BAEANQABCgIIAgABNQAFFAMIBwAZAGgLAA==.',
Mo='Modin:BAAANQAECgQIBgAAAA==.Mommacougar:BAAANQADCgIIAgAAAA==.Moon:BAAANQADCgUICgABNQADCgYIDwABAAAAAA==.Morawynd:BAAANQAECgQIBQAAAA==.Morlis:BAAANQAECgEIAQAAAA==.Morlock:BAABNQAECn8gAAIcAAgKFgtdlACuAQAcAAgKFgtdlACuAQAAAA==.Morningstahr:BAABNQAECn8gAAIMAAkKGRjliABtAgAMAAkKGRjliABtAgAAAA==.Morphìc:BAAANQAECgUIBgAAAA==.',
Mu='Munion:BAAANQAECgQJBAAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Mô']='Môrningstar:BAAANQADCgUIBQAAAA==.',
Na='Naaruto:BAAANQADCgEIAQAAAA==.Nanako:BAAANQADCggIIgAAAA==.Naravanta:BAAANQADCgUIBQAAAA==.Naughtyfused:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.Naughtyvoked:BAAANQADCgUIDgABNQAECgUIDAABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEIAQAAAA==.',
Ni='Nickayla:BAAANQAECgMIBQAAAA==.Nikkaya:BAAANQADCgYJBgABNQAECgUIEAABAAAAAA==.Nimblecow:BAAANQADCgEIAQAAAA==.',
No='Noobacleese:BAABNQAECn8hAAIZAAgKYBaviQAOAgAZAAgKYBaviQAOAgAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.Novarak:BAAANQADCgMIAwAAAA==.Noyn:BAAANQAECgEIAQABNQAECggIHgAeAKUiAA==.',
Ny='Nyghtrider:BAAANQAECgUIEAAAAA==.Nymëra:BAABNQAECn8WAAIRAAcKdguhlgBKAQARAAcKdguhlgBKAQAAAA==.Nyneeve:BAABNQAECn8XAAIOAAgKsgrGMQCQAQAOAAgKsgrGMQCQAQAAAA==.',
Od='Odinshunter:BAAANQADCgIIAgAAAA==.',
Ol='Olgrin:BAAANQADCgUIBQABNQADCgcIEgABAAAAAA==.',
On='Onepunch:BAAANQADCgcIBwAAAA==.Oneslice:BAAANQADCgYIBgAAAA==.',
Or='Orw:BAAANQAECgEIAQAAAA==.',
Pa='Palpatinee:BAAANQAECgUIBQAAAA==.Pandaloons:BAAANQABCgYICAABNQADCgYIBgABAAAAAA==.Papitochulo:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQAECgYIDAAAAA==.',
Pb='Pbób:BAAANQAECggICQAAAA==.',
Pe='Percocetpete:BAABNQAECn8kAAMKAAkKlh+KEgA0AwAKAAgKfCOKEgA0AwAOAAgKRgeINAB7AQAAAA==.Peregrine:BAAANQAECgEIAQAAAA==.',
Ph='Phaet:BAACNQAFFH8JAAMcAAQKRBbmHwD3AAAcAAMK7RrmHwD3AAAbAAEK8QzLHQBMAAA1AAQKfygAAxwACQq5H0M3AKwCABwACArdH0M3AKwCABsABAoHFecxAP4AAAAA.Phaux:BAAANQAECgEIAQAAAA==.',
Pi='Piper:BAAANQAECgQIBAAAAA==.',
Pl='Plâgue:BAABNQAECn8pAAIfAAkK/SH6HQDVAgAfAAkK/SH6HQDVAgAAAA==.',
Pr='Prot:BAAANQADCgUIBQAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgcIIwAWAOwmAA==.Puntthegnome:BAAANQADCgEIAQABNQAFFAYIFQAMACIWAA==.',
Ra='Rainforest:BAAANQAECgUIEAAAAA==.Raktoth:BAAANQADCggICAAAAA==.Ramden:BAABNQAECn8lAAIZAAgKTAcw1ABsAQAZAAgKTAcw1ABsAQAAAA==.Rampant:BAAANQAECgcIDwAAAA==.Rampscii:BAAANQAECgUICwABNQAECgcIDwABAAAAAA==.Randolier:BAABNQAECn8hAAIeAAgKaSIjKQDyAgAeAAgKaSIjKQDyAgAAAA==.Ratherton:BAACNQAFFH8VAAIMAAYKIhaDDwD2AQAMAAYKIhaDDwD2AQA1AAQKfy4AAgwACQphIlccAGUDAAwACQphIlccAGUDAAAA.Rathtard:BAABNQAECn8YAAIeAAkKzhhvQACnAgAeAAkKzhhvQACnAgABNQAFFAYIFQAMACIWAA==.Rauzer:BAAANQABCgIIAgAAAA==.Razz:BAAANQABCgIIAgAAAA==.',
Re='Renuwu:BAABNQAECn8zAAIKAAkK1gzPcADGAQAKAAkK1gzPcADGAQAAAA==.Resoluteone:BAABNQAECn8lAAILAAkKnwe1XwBwAQALAAkKnwe1XwBwAQAAAA==.Retnu:BAAANQADCgQICAAAAA==.Revelations:BAAANQAECgMIAwABNQAECgkJKAARAMEkAA==.Revytwohand:BAACNQAFFH8LAAIPAAQK0BkVCQBAAQAPAAQK0BkVCQBAAQA1AAQKfy0AAg8ACQpAHxkRANYCAA8ACQpAHxkRANYCAAAA.',
Rh='Rhok:BAAANQAECgEIAQAAAA==.',
Ro='Robonome:BAAANQADCgUIBQAAAA==.',
Ru='Rumii:BAAANQAECgQIBQAAAA==.',
['Rë']='Rëápër:BAAANQADCgIIAgAAAA==.',
['Rö']='Rödrïck:BAAANQAECgUICQABNQAECggIKQAcANoYAA==.',
Sa='Sabeladys:BAAANQAECgYIDwAAAA==.Saifir:BAABNQAECn8hAAMRAAcKTQhQogAsAQARAAcKTQhQogAsAQASAAUK3hB9vAAVAQAAAA==.Sallyd:BAAANQAECgEIAQAAAA==.Sardmagia:BAAANQAECgIIAgABNQAECgUJDAABAAAAAA==.Sardmongo:BAAANQAECgEIAQAAAA==.Sarduccini:BAAANQAECgUJDAAAAA==.',
Sh='Shadowpriest:BAAANQABCgIIAgAAAA==.Shamwowzer:BAAANQADCgQIBAAAAA==.Shelisaria:BAAANQAECgIIAgAAAA==.Shiftken:BAAANQADCgMIAwAAAA==.Shoktherapy:BAABNQAECn8ZAAMRAAcKfxsAUQAeAgARAAcKfxsAUQAeAgASAAEKAAClMwEyAAAAAA==.',
Si='Silvalus:BAAANQADCgcIEgAAAA==.Silvertide:BAABNQAECn8iAAMSAAgKFw/rcwDBAQASAAcKMxHrcwDBAQARAAcK3w4YigBtAQAAAA==.Sin:BAAANQADCgMIAwAAAA==.',
Sk='Skonka:BAAANQADCggICAAAAA==.Skyeforce:BAAANQADCggIDgAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
So='Soi:BAABNQAECn8eAAMeAAgKpSI4LgDhAgAeAAgKpSI4LgDhAgAgAAIKJA1+cgBpAAAAAA==.Solvent:BAAANQADCggICwAAAA==.Sondaar:BAAANQABCgcIDQAAAA==.Sonoforak:BAAANQAECgMJAwAAAA==.',
Sp='Sped:BAABNQAECn8jAAITAAgK7iHtBQALAwATAAgK7iHtBQALAwAAAA==.',
St='Staraleena:BAAANQAECgQIBAAAAA==.Stiffyhaze:BAAANQAECgQIBAAAAA==.Stillwët:BAAANQABCggICwAAAA==.Stingyr:BAAANQAECgUICgAAAA==.Stormslight:BAAANQAECgEIAQAAAA==.Stormsteel:BAAANQAECgEIAQAAAA==.Stossel:BAAANQAECgQICgAAAA==.',
Sw='Sweetie:BAAANQADCgYICgAAAA==.',
Ta='Tabio:BAAANQADCgYIBwAAAA==.Taboptics:BAAANQADCgEIAQAAAA==.Talas:BAABNQAECn8hAAINAAgKcRh8GwAPAgANAAgKcRh8GwAPAgAAAA==.Tamarack:BAAANQAECgEIAQAAAA==.Tanksabunch:BAABNQAECn8VAAIhAAkKlA0fqwCsAQAhAAkKlA0fqwCsAQABNQAFFAcIGwAgACkkAA==.',
Te='Tehmay:BAAANQADCgIIAgAAAA==.Tenssid:BAAANQADCggIGAAAAA==.Terrormisu:BAAANQAECgYIBwAAAA==.',
Th='Thorclap:BAAANQAECgEJAQAAAA==.Thundertaker:BAAANQADCgYICgAAAA==.',
Ti='Tim:BAAANQADCggJCgABNQAECgkJJAAJAEggAA==.Tiniashio:BAAANQAECgQIBAABNQAECgUIDAABAAAAAA==.',
To='Tooru:BAABNQAECn8uAAMeAAkK2SL1EgBSAwAeAAkK2SL1EgBSAwAgAAgKqA/1NACiAQAAAA==.',
Tr='Traest:BAAANQAECgEIAQAAAA==.Triena:BAAANQADCggJCAAAAA==.Trimas:BAAANQAECgEIAQAAAA==.',
Tt='Tt:BAAANQAECggIBQAAAA==.',
Tw='Twinkles:BAABNQAECn8jAAMDAAgKLhRgWgAHAgADAAgKLhRgWgAHAgAZAAEKzwfHsAEsAAAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ul='Ulysius:BAABNQAECn8aAAIZAAgKmRMnlgDzAQAZAAgKmRMnlgDzAQAAAA==.',
Un='Unfazed:BAAANQADCgIIAgAAAA==.',
Va='Valkisek:BAABNQAECn8bAAIQAAkKGBlVBwB6AgAQAAkKGBlVBwB6AgAAAA==.Vallarfax:BAABNQAECn8hAAIeAAgKyhvtTgB/AgAeAAgKyhvtTgB/AgAAAA==.Vandro:BAABNQAECn8qAAIDAAgKbBO0XgD5AQADAAgKbBO0XgD5AQAAAA==.Varea:BAAANQAECgYICwABNQAECgkJLQAMANcUAA==.Vashdk:BAACNQAFFH8LAAILAAQKxBy5DwBUAQALAAQKxBy5DwBUAQA1AAQKfyoAAgsACQp3JGsIAHcDAAsACQp3JGsIAHcDAAAA.',
Ve='Velcyn:BAAANQAFFAIIBAAAAA==.Veloranas:BAABNQAECn8tAAMMAAkK1xQOcACdAgAMAAkKyRQOcACdAgAQAAMK3xESKwCeAAAAAA==.Venjince:BAAANQADCgYIBgAAAA==.Venôm:BAAANQADCgQIBAAAAA==.Vespyr:BAAANQAECgUICAABNQAECgUICgABAAAAAA==.Vewdoo:BAABNQAECn8kAAISAAkKECLGDQB5AwASAAkKECLGDQB5AwAAAA==.Vexiara:BAAANQADCgcIDwABNQAECgcICgABAAAAAA==.',
Vi='Vizimir:BAAANQAECgMIBQAAAA==.',
Vy='Vynstabbin:BAAANQAECgUJCgABNQAECgYICwABAAAAAA==.',
Wa='Waiwai:BAAANQADCgcIBwAAAA==.Warfarin:BAAANQADCgMIAwAAAA==.Wascii:BAAANQAECgQIDAABNQAECgcIDwABAAAAAA==.',
We='Weaken:BAAANQAECgYIBgAAAA==.',
Wh='Whiskeybear:BAAANQADCgYICAAAAA==.',
Wi='Willy:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Wivvy:BAAANQAECgYIBgAAAA==.Wizkerbizkit:BAABNQAECn8ZAAMgAAcKmgY2TAD9AAAgAAYKfAc2TAD9AAAeAAEKEwMXYgEtAAAAAA==.',
Wo='Wolfcaza:BAAANQADCgcIDgAAAA==.Wooshira:BAAANQADCgUIDgAAAA==.',
Wy='Wyrmheal:BAABNQAECn8sAAIOAAkKGiHCBwBdAwAOAAkKGiHCBwBdAwAAAA==.Wyvvie:BAABNQAECn8YAAIiAAkKIRO6FAAsAgAiAAkKIRO6FAAsAgAAAA==.',
Ya='Yamihime:BAABNQAECn8hAAMIAAkKWhkhIQCOAgAIAAkKWhkhIQCOAgACAAEKAAB/bAAxAAAAAA==.Yatiri:BAAANQAECgYIBgAAAA==.',
Za='Zalinis:BAAANQADCgYICAAAAA==.Zambas:BAAANQAECgMIAwAAAA==.',
Ze='Zeaket:BAACNQAFFH8aAAIjAAYKbyA4AABRAgAjAAYKbyA4AABRAgA1AAQKfy4AAiMACQo2JcEAAJkDACMACQo2JcEAAJkDAAAA.Zephyr:BAAANQADCgcIIQABNQAECgUICgABAAAAAA==.Zerrayna:BAAANQADCgYICwAAAA==.Zeçhs:BAAANQAECgQIBAABNQAECggIHgAeAKUiAA==.',
Zi='Zinbad:BAAANQADCggIHwAAAA==.',
Zo='Zorcan:BAAANQAECgQIBgAAAA==.',
Zu='Zugzugz:BAAANQAECggICAAAAA==.Zulfilith:BAAANQADCgcIGgAAAA==.',
['Zà']='Zàrgothrax:BAAANQADCgYIBgAAAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Än']='Äncïênt:BAAANQADCgcIBwAAAA==.',
['Ða']='Ðachee:BAABNQAECn8cAAIKAAgKfiDrHQD3AgAKAAgKfSDrHQD3AgAAAA==.',
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
