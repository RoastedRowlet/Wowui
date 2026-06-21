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

local lookup = {'Warrior-Fury','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Rogue-Outlaw','Druid-Guardian','Warrior-Protection','DeathKnight-Blood','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Destruction','Druid-Balance','Paladin-Holy','Priest-Discipline','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Druid-Feral','Hunter-Survival','Warlock-Affliction','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ab='Abugarcia:BAAALgAECgUJBwAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAABLgAECn8aAAIBAAgJxxF8AwCYAAABAAgJxxF8AwCYAAAAAA==.Akusenshi:BAABLgAECn8UAAIBAAcJOxBcOgBcAQABAAcJOxBcOgBcAQAAAA==.',
Al='Alarr:BAAALgAECgYJBwABLgAFFAQJDgACAOwYAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAABLgAECn8hAAMDAAgJ0xgNQQD/AQADAAgJ0xgNQQD/AQAEAAEJxxCHOgAzAAAAAA==.Alexi:BAAALgADCgkJCwAAAA==.Alivis:BAEALgAECgQJBAABLgAECgkJMgAFAJYiAA==.Alzith:BAAALgAECgQJBQABLgAECgkJIQADAI0cAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAkJPgAHAFclAA==.Animocity:BAAALgAECgIJAgAAAA==.',
Ap='Apexalpha:BAAALgAECgQJCAAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Arius:BAAALgADCgUJBQAAAA==.Armster:BAAALgAECgcJCgAAAA==.Arold:BAABLgAECn8lAAIIAAkJRhaONAAHAgAIAAkJRhaONAAHAgAAAA==.',
As='Asylia:BAACLgAFFH8KAAIJAAQJNhGCCQA5AQAJAAQJNhGCCQA5AQAuAAQKfxcAAgkACAlLGy4hABcCAAkACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8jAAIKAAgJqg57QQBoAQAKAAgJqg57QQBoAQAAAA==.',
Au='Aulendil:BAAALgAECgEJAQAAAA==.Aurelliae:BAABLgAECn8WAAIFAAgJtBWSVACmAQAFAAgJtBWSVACmAQAAAA==.',
Av='Avesiren:BAABLgAECn8qAAILAAgJsxKlGgBDAQALAAgJsxKlGgBDAQAAAA==.',
Ax='Axxion:BAAALgADCgYJBgAAAA==.',
Ay='Ayidá:BAAALgAECggJEwAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAABLgAECn8ZAAIMAAkJpghRAwATAQAMAAkJpghRAwATAQAAAA==.Babymamaa:BAABLgAECn8VAAINAAYJRwWEaQCrAAANAAYJRwWEaQCrAAAAAA==.Babymuffins:BAABLgAECn8oAAIMAAgJqB8YIwB5AgAMAAgJqB8YIwB5AgAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAABLgAECn8UAAINAAgJYwlISAATAQANAAgJYwlISAATAQAAAA==.Beklee:BAAALgADCgYJBgAAAA==.Belanda:BAAALgAECgYJDAAAAA==.Belgord:BAAALgAECgYJEwAAAA==.Belin:BAAALgADCgkJFgAAAA==.Bellyn:BAAALgAECggJCAAAAA==.Belmond:BAAALgAECgQJCAAAAA==.Belzac:BAAALgAECgMJAwAAAA==.Bemuse:BAAALgADCgcJDAAAAA==.',
Bl='Blackmill:BAABLgAECn8UAAIOAAgJZBohBQAuAgAOAAgJZBohBQAuAgAAAA==.Blayrog:BAABLgAECn8qAAICAAgJuBTZbgCcAQACAAgJuBTZbgCcAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8vAAMPAAkJGBiuDQAOAgAPAAkJzReuDQAOAgABAAYJ/RDSUQBiAQABLgAFFAcJGAAQADEUAA==.Bobamood:BAAALgAFFAIJAgAAAA==.Bobbyknocker:BAAALgAECgcJCAAAAA==.Bolf:BAABLgAECn8gAAMRAAYJGQ4JAQAdAQARAAYJJgsJAQAdAQASAAYJ9AueEQDwAAAAAA==.Boneharnen:BAAALgAECgYJDAAAAA==.Boombaaby:BAABLgAECn8vAAIFAAgJMA78XACPAQAFAAgJMA78XACPAQAAAA==.Boomkittie:BAAALgADCgYJBgAAAA==.Bootzee:BAABLgAECn8gAAIJAAcJbxu1KAAbAgAJAAcJbxu1KAAbAgAAAA==.',
Br='Brewglaive:BAAALgAECgEJAwAAAA==.Brewsli:BAAALgAECgMJAwAAAA==.Britishchick:BAAALgAECgYJBgABLgAECggJKAATAJMdAA==.Brookenoel:BAABLgAECn8mAAIQAAkJ2gj9LwBfAQAQAAkJ2gj9LwBfAQAAAA==.Brunhilian:BAAALgAECgUJDQAAAA==.',
Bs='Bsê:BAAALgAECgIJAgAAAA==.',
Bu='Buckmaster:BAAALgAECgUJDQAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAABLgAECn8oAAIBAAgJXQf1RwAlAQABAAgJXQf1RwAlAQAAAA==.Calada:BAABLgAECn8eAAIHAAYJIwMTAwCEAAAHAAYJIwMTAwCEAAAAAA==.Callypso:BAAALgAECgYJBgABLgAECggJIwAKAKoOAA==.Carbion:BAAALgADCgkJCQAAAA==.',
Ce='Cedarnia:BAAALgADCggJBwAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAgAGAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8eAAIJAAkJOxbFHwBRAgAJAAkJOxbFHwBRAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJDgAAAA==.',
Ck='Ckrazykanaka:BAAALgADCgEJAQAAAA==.',
Co='Corrynn:BAAALgAECgcJEgAAAA==.',
Cr='Cribbage:BAACLgAFFH8JAAIUAAMJwB5JFwDhAAAUAAMJwB5JFwDhAAAuAAQKfykAAxQACQlJIm4FAMECABQACQlJIm4FAMECAA8AAQnMGrFtAEYAAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgADCggJEAAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgUJEwAAAA==.',
Cv='Cvaluenigma:BAAALgAECgEJAQAAAA==.',
Cy='Cynosure:BAABLgAECn8xAAIRAAkJvRkcEQAgAgARAAkJvRkcEQAgAgABLgAFFAEJAwAGAAAAAA==.Cytronsneak:BAABLgAECn8UAAIRAAYJEw7yLwAgAQARAAYJEw7yLwAgAQAAAA==.',
Da='Dabb:BAAALgAECgIJAgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgUJDQAAAA==.Daela:BAAALgADCgYJBgAAAA==.Daliå:BAAALgAECgEJAQAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8kAAIIAAkJdgywVwCWAQAIAAkJdgywVwCWAQAAAA==.Darkheaven:BAABLgAECn8eAAIMAAkJagoLdQCEAQAMAAkJagoLdQCEAQAAAA==.Darkkanaka:BAAALgADCgEJAgAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgMJAwAAAA==.Dazarek:BAABLgAECn8pAAIVAAkJPAZgAgCIAAAVAAkJPAZgAgCIAAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8aAAIWAAcJYhl9KwB6AQAWAAcJYhl9KwB6AQAuAAQKfykAAhYACAmMIsUeAFwCABYACAmMIsUeAFwCAAEuAAQKBQkKAAYAAAAA.Demonkanaka:BAAALgADCgMJBQAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgAECgUJBQAAAA==.Devinetoro:BAABLgAECn8uAAIMAAkJVQhThgBjAQAMAAkJVQhThgBjAQAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAIXAAkJGRcmLAD/AQAXAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn83AAQYAAkJExoyAwBsAgAYAAkJExoyAwBsAgAZAAQJTRIzLQCBAAAaAAMJLQYgeQBxAAAAAA==.',
Dk='Dklunar:BAABLgAFFH8FAAIDAAQJ5wETywCYAAADAAQJ5wETywCYAAAAAA==.',
Do='Doree:BAAALgAECgUJBQAAAA==.Dotdotoops:BAAALgAECgEJAQAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAUJFwAbAGsUAA==.Dreadsofdeth:BAABLgAECn8VAAICAAYJixh1ngCZAQACAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJEAAAAA==.Drklhtkanaka:BAAALgAECgEJAQAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.Drustone:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8yAAIIAAgJBBI4VgCaAQAIAAgJBBI4VgCaAQAAAA==.',
Eh='Ehtar:BAAALgAECgYJBgABLgAFFAcJGAAQADEUAA==.',
Ei='Einheri:BAABLgAECn8uAAIBAAkJfxzyEQBkAgABAAkJfxzyEQBkAgAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgAECgYJCAAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8UAAIRAAMJyiBpIgASAQARAAMJyiBpIgASAQAuAAQKfywAAhEACQkvGmkPADYCABEACQkvGmkPADYCAAAA.Enoira:BAAALgAECgEJAgAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAABLgAECn8hAAILAAYJ1xb6AAAHAQALAAYJ1xb6AAAHAQAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Et='Ethel:BAAALgAECgEJAQAAAA==.',
Ev='Evillizard:BAABLgAECn8XAAIaAAgJ2wpgQAAoAQAaAAgJ2wpgQAAoAQAAAA==.',
Ex='Exhumer:BAABLgAECn8nAAIMAAkJoCV4DgDyAgAMAAkJoCV4DgDyAgAAAA==.',
Fa='Faffard:BAABLgAECn8dAAIFAAYJrxHTgwA3AQAFAAYJrxHTgwA3AQABLgAECgkJOQAcAEUJAA==.Fame:BAAALgAFFAEJAQABLgAFFAYJGAAaAPkXAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgUJBgAAAA==.',
Fe='Fearbilly:BAAALgAECgUJCQAAAA==.Felbilly:BAAALgAECgEJAQAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAABLgAECn8jAAMXAAYJDQQPAwCFAAAXAAYJDQQPAwCFAAAdAAEJrAHoqgASAAAAAA==.',
Fl='Flap:BAACLgAFFH8YAAIaAAYJ+RcpIQBXAQAaAAYJ+RcpIQBXAQAuAAQKfx4AAxoACQntG24cAOQBABoACQntG24cAOQBABgAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fu='Funenix:BAAALgADCgUJBQAAAA==.Furbalkanaka:BAAALgADCgEJAQAAAA==.',
Fy='Fystie:BAABLgAECn8tAAMXAAYJzhlZAQAmAQAXAAYJzhlZAQAmAQAdAAUJXw6eUQDHAAABLgAECgkJOQAcAEUJAA==.',
Ga='Galacticfox:BAAALgAECgIJAgAAAA==.Galpally:BAABLgAECn8nAAIMAAcJ5xNbgABuAQAMAAcJ5xNbgABuAQAAAA==.Ganzar:BAAALgADCgMJBAABLgAFFAMJEwADAMMkAA==.Garin:BAAALgAECgUJBgAAAA==.',
Ge='Genma:BAAALgAECgQJBAAAAA==.Gennic:BAAALgADCgcJBwAAAA==.Gettinskins:BAAALgAECgMJAwAAAA==.',
Gi='Gishongar:BAAALgAECgkJCgAAAA==.',
Gl='Glorak:BAABLgAECn8nAAIFAAcJdgj6igApAQAFAAcJdgj6igApAQAAAA==.',
Gr='Grashen:BAABLgAECn8oAAIJAAgJ0RlCKQAYAgAJAAgJ0RlCKQAYAgAAAA==.Gravorik:BAABLgAFFH8KAAMLAAMJPAdZAQBwAAALAAMJXgVZAQBwAAAMAAEJbwfVuQBDAAAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDwAAAA==.',
Gs='Gsm:BAABLgAECn8+AAINAAkJkhoKDwB/AgANAAkJkhoKDwB/AgAAAA==.',
Gu='Gulritz:BAAALgAECgIJAgAAAA==.Gulrum:BAAALgADCgEJAQAAAA==.Gurlyman:BAAALgAECgYJDgAAAA==.',
Ha='Haikara:BAAALgADCgMJAwAAAA==.Hante:BAAALgADCgcJEAAAAA==.Hartmonster:BAAALgAECgQJCAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMFAAcJIQVmbQAfAQAFAAYJ0gVmbQAfAQAbAAEJrwGBRgAbAAAAAA==.Hideous:BAAALgAECgQJCQAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgYJEwAAAA==.Hotspur:BAAALgAECgMJAwABLgAECggJKAAXAPQVAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ia='Iaanditos:BAAALgADCgYJBgAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilisselia:BAAALgADCgcJBwAAAA==.Ilokana:BAAALgAECgUJDgAAAA==.Ilostmybible:BAAALgAECgIJAgAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAABLgAECn8ZAAIBAAYJXxONQgA7AQABAAYJXxONQgA7AQAAAA==.',
It='Itzbarney:BAAALgAECggJEwAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacsknight:BAAALgAECgUJBwAAAA==.Jacspally:BAABLgAECn8qAAMMAAkJdR6uAABUAgAMAAkJdR6uAABUAgAeAAEJ0AP6nQAiAAAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8jAAITAAkJkSAjBADZAgATAAkJkSAjBADZAgAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAABLgAECn83AAMdAAkJ8xQ4FwATAgAdAAkJ8xQ4FwATAgATAAEJAAQajQARAAAAAA==.Jellexy:BAABLgAECn8sAAICAAYJTgVUBgC4AAACAAYJTgVUBgC4AAAAAA==.',
Ji='Jimlahey:BAAALgAECgMJAwABLgAFFAUJGQACADEfAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8eAAIKAAUJ2xYIBAD9AAAKAAUJ2xYIBAD9AAAuAAQKfzIAAgoACQn5HEsRAJYCAAoACQn5HEsRAJYCAAAA.Jonnyfive:BAABLgAECn8WAAIMAAYJBxH5sgAbAQAMAAYJBxH5sgAbAQAAAA==.',
['Jó']='Jósepha:BAAALgADCgQJBAAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIFAAkJ6hfqLwAdAgAFAAkJ6hfqLwAdAgAAAA==.Kaisa:BAAALgAECgEJAgAAAA==.Kalimthor:BAAALgADCgEJAQAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAABLgAECn8eAAIMAAgJZBR+VgDHAQAMAAgJZBR+VgDHAQAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8tAAMFAAkJAh2vCAAzAgAFAAgJvyCvCAAzAgAbAAYJEw3CCgBuAQAuAAQKf0EAAxsACQkiJo8CAIkDABsACQkYIo8CAIkDAAUACQkiJiMHACUDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgUJBQAAAA==.Keheo:BAAALgAECgQJCwAAAA==.Kendrimore:BAAALgAECgYJBgAAAA==.',
Kh='Khandragho:BAAALgAECgYJBgAAAA==.Khaza:BAAALgAECgUJBQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kiri:BAAALgAECgMJBAABLgAECgkJNQAfAEMRAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn9PAAIEAAkJGSKQAQAdAwAEAAkJGSKQAQAdAwAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIeAAkJbRfBJgD0AQAeAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgUJDgAAAA==.Kruger:BAABLgAECn8jAAIIAAcJ+geLoQD8AAAIAAcJ+geLoQD8AAAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.Krzyhayn:BAAALgADCgUJBQAAAA==.Krzykanaka:BAAALgADCgIJBAAAAA==.',
Kt='Ktanna:BAABLgAECn8XAAIgAAcJaAjNNQDlAAAgAAcJaAjNNQDlAAAAAA==.',
Ku='Kublakhan:BAAALgAECgkJEAAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAYJLwALABMeAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8gAAIJAAkJixwNKgAUAgAJAAkJixwNKgAUAgAAAA==.Lapras:BAEBLgAFFH8OAAMaAAUJeyaKFgC4AQAaAAUJeyaKFgC4AQAYAAEJ6iUNCwBxAAAAAA==.Lateralus:BAABLgAECn8vAAIMAAkJvhnGKABfAgAMAAkJvhnGKABfAgAAAA==.Laureli:BAABLgAECn8mAAIBAAYJmAU+AwCjAAABAAYJmAU+AwCjAAAAAA==.',
Le='Leeta:BAABLgAECn8oAAITAAgJkx3ZCQBLAgATAAgJkx3ZCQBLAgAAAA==.Legendx:BAAALgADCgUJBwAAAA==.Letholdus:BAABLgAECn8bAAIEAAkJHhY7AADqAQAEAAkJHhY7AADqAQAAAA==.',
Li='Lightningg:BAABLgAECn8fAAIYAAkJAAyyCQCLAQAYAAkJAAyyCQCLAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgABLgAFFAQJDgACAOwYAA==.',
Lo='Loahavemercy:BAAALgAECgEJAQAAAA==.Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAABLgAECn8UAAILAAYJsgQaNwCDAAALAAYJsgQaNwCDAAAAAA==.Losoz:BAAALgAECgEJAgAAAA==.',
Lu='Lucariel:BAABLgAECn8hAAIDAAkJjRwZGAC2AgADAAkJjRwZGAC2AgAAAA==.Lusilsandrus:BAAALgAECgYJEwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAABLgAFFH8HAAIJAAMJEA7DUgCtAAAJAAMJEA7DUgCtAAAAAA==.Magusbilly:BAAALgAECgQJBAAAAA==.Mahoutsukai:BAABLgAECn8gAAICAAkJKQP0rQAlAQACAAkJKQP0rQAlAQAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8oAAINAAgJXQjsSQANAQANAAgJXQjsSQANAQAAAA==.',
Me='Mechaknight:BAAALgAECgUJCgAAAA==.',
Mi='Mildrik:BAABLgAECn8fAAIBAAkJCQrYMQCFAQABAAkJCQrYMQCFAQAAAA==.Miracledh:BAABLgAECn8aAAIgAAgJkiVWBgDSAgAgAAgJkiVWBgDSAgAAAA==.Mirkdrak:BAABLgAECn8iAAMaAAYJuguAUgDlAAAaAAYJuguAUgDlAAAYAAMJyQJmNgBjAAAAAA==.Mishach:BAAALgAECgQJBAABLgAECggJAgAGAAAAAA==.Misheard:BAACLgAFFH8DAAIWAAIJmBGNmQBCAAAWAAIJmBGNmQBCAAAuAAQKfzoAAhYACQnKIP0UAJsCABYACQnKIP0UAJsCAAAA.Misjudged:BAABLgAECn8YAAQaAAgJexOzLwB5AQAaAAgJexOzLwB5AQAYAAQJhw0dKQDWAAAZAAIJghjnOwA0AAAAAA==.Missus:BAAALgAFFAMJAwAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgQJBQAAAA==.Mizzen:BAABLgAECn8rAAMhAAkJ/R+uBgDfAgAhAAkJ/R+uBgDfAgAiAAEJawRSpwAdAAABLgAFFAcJGAAQADEUAA==.',
Mo='Mohtavius:BAABLgAECn82AAIUAAkJlhlOCgBMAgAUAAkJlhlOCgBMAgAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn85AAIcAAkJRQmyEQAtAQAcAAkJRQmyEQAtAQAAAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Mu='Mulnier:BAAALgADCgkJCgAAAA==.Munkìe:BAAALgAECgUJDQABLgAECgkJPgANAJIaAA==.Muura:BAABLgAECn8hAAIDAAkJEA33pwAgAQADAAkJEA33pwAgAQAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJEgAAAA==.',
Na='Nakavelli:BAAALgAECgEJAQAAAA==.Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8tAAIJAAkJZR2gDgDfAgAJAAkJZR2gDgDfAgAAAA==.Nattal:BAAALgADCgUJBQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJDAAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAgJLAAZAOIdAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Ot='Otwin:BAABLgAECn8aAAMJAAYJ7hWWSwCCAQAJAAYJ7hWWSwCCAQANAAEJnAfMtgAlAAAAAA==.',
Pa='Pahuum:BAAALgAECgYJEwAAAA==.Paimon:BAABLgAECn8cAAILAAgJJxyCCgAhAgALAAgJJxyCCgAhAgABLgAFFAYJGAAaAPkXAA==.Paintrainn:BAABLgAECn8XAAIJAAgJdgGonQCVAAAJAAgJdgGonQCVAAAAAA==.Palewhiteman:BAABLgAECn8hAAIeAAgJ5hm6GwAmAgAeAAgJ5hm6GwAmAgAAAA==.Palleigh:BAABLgAECn8tAAIeAAkJoxC1AACdAQAeAAkJoxC1AACdAQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Parodoxx:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8oAAIXAAgJ9BUELQD0AQAXAAgJ9BUELQD0AQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8kAAIFAAkJTxmUKAA9AgAFAAkJTxmUKAA9AgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Pl='Plague:BAAALgAFFAIJAgABLgAFFAMJEwADAMMkAA==.',
Po='Poondor:BAABLgAECn8aAAIeAAkJRRSvGwAmAgAeAAkJRRSvGwAmAgAAAA==.',
Pr='Praylorswíft:BAAALgAECgMJAwABLgAECgkJIAACAJ4PAA==.Predaturd:BAAALgAECggJBQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Py='Pyxis:BAAALgADCgEJAQAAAA==.',
Qi='Qindere:BAABLgAECn8VAAICAAcJmQMA/gD/AAACAAcJmQMA/gD/AAAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn9EAAIFAAkJPhqvIwBUAgAFAAkJPhqvIwBUAgAAAA==.Rakshaman:BAABLgAECn8VAAIJAAgJSQr/BAB4AAAJAAgJSQr/BAB4AAAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgYJCwABLgAFFAMJEwADAMMkAA==.',
Re='Reihino:BAAALgAECgYJCgAAAA==.Resbak:BAABLgAECn8ZAAIdAAgJ3w7bLQBsAQAdAAgJ3w7bLQBsAQAAAA==.Resiaus:BAABLgAECn89AAIZAAkJyRyZBADgAgAZAAkJyRyZBADgAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECgcJDwAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Robinho:BAAALgAECgcJDQAAAA==.Rocketabu:BAAALgAECgMJBwAAAA==.Roctheist:BAABLgAECn8UAAMQAAYJEAbHSAC8AAAQAAYJEAbHSAC8AAAHAAYJEwZZTwCjAAAAAA==.Rocthoeb:BAABLgAECn80AAIUAAkJxRH/EQDoAQAUAAkJxRH/EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.Rokstedy:BAAALgAECgEJAQAAAA==.',
Ry='Ry:BAABLgAECn8qAAMjAAkJOSPtAQAWAwAjAAkJOSPtAQAWAwAXAAEJ8ASk+gAaAAAAAA==.',
Sa='Saeris:BAAALgAECgUJBwAAAA==.Saintalpha:BAEALgAECgEJAQABLgAECggJFQAfAJkTAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFQAfAJkTAA==.Saintkhal:BAEALgAECgQJDQABLgAECggJFQAfAJkTAA==.Saintmedicus:BAEBLgAECn8VAAMfAAgJmRMAOAAzAQAfAAUJZBcAOAAzAQAQAAMJ0w3YYQCSAAAAAA==.Saintshammy:BAABLgAFFH8FAAIJAAMJWxXoSgDFAAAJAAMJWxXoSgDFAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Saki:BAAALgADCgUJBQAAAA==.Sanctor:BAABLgAECn8dAAIeAAcJeyJ0EgB/AgAeAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Sangairee:BAAALgAECgEJAQAAAA==.Saraya:BAABLgAECn8XAAIeAAkJDRelHgANAgAeAAkJDRelHgANAgAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8jAAIfAAkJYh2RCADsAgAfAAkJYh2RCADsAgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shanoodles:BAAALgAECgUJCQAAAA==.Shibaryotaro:BAAALgAECgEJAQAAAA==.Shiftee:BAAALgAECgQJBAABLgAECgcJHAAFABsWAA==.Shinstabber:BAABLgAECn8jAAIVAAkJARTPEwDWAQAVAAkJARTPEwDWAQAAAA==.Shivantice:BAAALgAECgUJAgAAAA==.Shivantis:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Shruggie:BAABLgAECn81AAMgAAgJARjcAAA8AQAgAAgJARjcAAA8AQAWAAQJDAO+/QBOAAAAAA==.',
Si='Silven:BAAALgAECgYJDgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8aAAIKAAkJpxn+EgCEAgAKAAkJpxn+EgCEAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8cAAIFAAcJGxZxLwD0AQAFAAcJGxZxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgAECgYJCQAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8tAAMbAAkJuwenEwAmAQAkAAgJKATNLQA3AQAbAAkJnAenEwAmAQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAJADYRAA==.Starlie:BAAALgAECgUJDgAAAA==.Stormstrike:BAAALgAECgcJBgAAAA==.Stratacaster:BAABLgAECn8YAAIIAAcJ0QKH1gCpAAAIAAcJ0QKH1gCpAAAAAA==.Strawberry:BAAALgAFFAEJAQAAAA==.Stuckinwell:BAACLgAFFH8FAAMIAAIJkBjuNQCnAAAIAAIJGBDuNQCnAAAcAAEJlBbZJgBHAAAuAAQKfxsAAwgACQn6GsEzAD0CAAgACAnpFsEzAD0CABwABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAIXAAIJhh6QFQC3AAAXAAIJhh6QFQC3AAABLgAFFAgJLAAZAOIdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDwABLgAECgkJTQAVAJUZAA==.Synfyl:BAAALgAECgUJCAAAAA==.Synpathi:BAEALgADCgEJAQABLgAFFAIJBgAlACoGAA==.Synsyn:BAECLgAFFH8GAAMlAAIJKgZ1EQCDAAAlAAIJKgZ1EQCDAAAIAAEJVgDK2AAjAAAuAAQKf1QAAyUABwnSE6cNAIIBACUABwnSE6cNAIIBAAgABgnQCXyyAOAAAAAA.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8gAAICAAkJng+eiABmAQACAAkJng+eiABmAQAAAA==.',
Te='Teanfists:BAAALgAECgYJCgAAAA==.Temna:BAABLgAECn86AAIMAAkJBiT4BQBDAwAMAAkJBiT4BQBDAwAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAABLgAECn8mAAIFAAYJYx3VAQCaAQAFAAYJYx3VAQCaAQAAAA==.Thespaniard:BAABLgAECn8fAAIQAAkJqxj0FAAmAgAQAAkJqxj0FAAmAgAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAABLgAECn8WAAITAAgJlQl2MADpAAATAAgJlQl2MADpAAABLgAFFAEJAQAGAAAAAA==.Tinbasher:BAAALgAECgYJDAAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Toast:BAAALgADCgEJAQAAAA==.Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAABLgAECn8eAAMXAAkJ7gnJSQBnAQAXAAkJ7gnJSQBnAQAdAAEJ5QxCjgAyAAAAAA==.Tricky:BAAALgAECgYJEQAAAA==.Triviousox:BAABLgAECn8aAAIMAAcJwhD/jwBSAQAMAAcJwhD/jwBSAQAAAA==.Tryxx:BAAALgADCgUJBQAAAA==.Trêehugger:BAAALgAECgEJAQABLgAECgUJCQAGAAAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAFFAUJEAAmAMYdAA==.Twotvmage:BAABLgAECn8uAAMCAAkJJB2tKQB0AgACAAkJJB2tKQB0AgAmAAEJIA1+GAAuAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Uneedarez:BAAALgAECgQJBAAAAA==.Unglued:BAAALgAECgYJBgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJDQABLgAECgkJNwAIAA8cAA==.',
Up='Uplift:BAABLgAFFH8FAAIhAAQJXRhDEgAqAQAhAAQJXRhDEgAqAQABLgAFFAgJHgACAJsbAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Ut='Uttrsdeek:BAAALgAFFAMJBAAAAA==.',
Va='Vale:BAAALgAECggJCAAAAA==.Valkky:BAABLgAECn83AAMnAAkJXRbwBwD8AQAnAAkJsxXwBwD8AQAWAAQJOA0VowDOAAAAAA==.Valky:BAAALgAECgEJAQABLgAECgkJNwAnAF0WAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn81AAQfAAkJQxGwHgDZAQAfAAkJ9A2wHgDZAQAHAAcJiw9CNgAnAQAQAAIJ2wRXfQBDAAAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vanity:BAAALgAECgUJBQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECggJEAABLgAECgkJNQAfAEMRAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn85AAIFAAkJbx4LEQDIAgAFAAkJbx4LEQDIAgAAAA==.Vessna:BAABLgAECn8iAAICAAYJIAd63gDdAAACAAYJIAd63gDdAAABLgAECgYJIgAaALoLAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAABLgAECn8nAAIjAAcJJiM6AADhAQAjAAcJJiM6AADhAQAAAA==.',
Vm='Vmro:BAAALgADCgYJFgAAAA==.',
Vo='Voras:BAAALgAECgYJEQAAAA==.Vorttex:BAAALgAECgUJEQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHQAaAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8oAAInAAgJvRpGBwAQAgAnAAgJvRpGBwAQAgAAAA==.',
Wh='Whiskeyrick:BAAALgAECgUJBwAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJBAAAAA==.Winters:BAAALgAECgEJAQAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIQAAgJ4RsHEQB4AgAQAAgJ4RsHEQB4AgAAAA==.',
Xi='Xivago:BAAALgAECgUJCQAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAACLgAFFH8HAAIkAAMJcQj0IgDBAAAkAAMJcQj0IgDBAAAuAAQKfxYAAyQACAkDDhIlAHUBACQACAkDDhIlAHUBABsABAmABINqAJQAAAAA.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yo='Yoshino:BAAALgAECgUJBgABLgAECgYJIAACAC8IAA==.',
Yu='Yuzuriha:BAAALgAECgYJDwAAAA==.',
Za='Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgAECgcJDAAAAA==.',
Zo='Zophier:BAAALgAECgQJBgAAAA==.Zouk:BAAALgAECgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAABLgAECn8YAAIbAAcJhwzQFQALAQAbAAcJhwzQFQALAQAAAA==.',
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
