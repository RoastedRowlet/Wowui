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

local lookup = {'Warrior-Fury','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Rogue-Outlaw','Druid-Guardian','Warrior-Protection','DeathKnight-Blood','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Warlock-Destruction','Druid-Balance','Hunter-Marksmanship','Paladin-Holy','Priest-Discipline','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement','Druid-Feral','Warlock-Affliction','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ab='Abugarcia:BAAALgAECgUJBwAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akiryss:BAABLgAECn8bAAIBAAkJORJ8CADhAAABAAkJORJ8CADhAAAAAA==.Akusenshi:BAABLgAECn8UAAIBAAcJOxBdOgBcAQABAAcJOxBdOgBcAQAAAA==.',
Al='Alarr:BAAALgAECgYJBwABLgAFFAQJDgACAOwYAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alenthia:BAAALgADCgEJAQAAAA==.Alethrix:BAABLgAECn8hAAMDAAgJ0xgQQQD/AQADAAgJ0xgQQQD/AQAEAAEJxxCIOgAzAAAAAA==.Alexi:BAAALgADCgkJCwAAAA==.Alivis:BAEALgAECgQJBwABLgAFFAMJBQAFAK0VAA==.Alzith:BAAALgAECgQJBQABLgAECgkJIQADAI0cAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAkJRwAHAFclAA==.Animocity:BAAALgAECgQJBgAAAA==.',
Ap='Apexalpha:BAAALgAECgQJCAAAAA==.Appletinni:BAAALgAECgcJCQAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Arius:BAAALgADCgUJBQAAAA==.Armster:BAAALgAECgcJCgAAAA==.Arold:BAABLgAECn8rAAIIAAkJnRaPNAAHAgAIAAkJnRaPNAAHAgAAAA==.',
As='Asylia:BAACLgAFFH8KAAIJAAQJNhGCCQA5AQAJAAQJNhGCCQA5AQAuAAQKfxcAAgkACAlLGy4hABcCAAkACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8kAAIKAAkJCA57QQBoAQAKAAkJCA57QQBoAQAAAA==.',
Au='Aulendil:BAAALgAECgEJAQAAAA==.Aurelliae:BAABLgAECn8WAAIFAAgJtBWSVACmAQAFAAgJtBWSVACmAQAAAA==.',
Av='Avesiren:BAABLgAECn8xAAILAAkJwRVNAQDcAQALAAkJwRVNAQDcAQAAAA==.',
Ax='Axxion:BAAALgADCgYJBgAAAA==.',
Ay='Ayidá:BAAALgAECggJEwAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAABLgAECn8bAAIMAAkJowjRDgAEAQAMAAkJowjRDgAEAQAAAA==.Babymamaa:BAABLgAECn8VAAINAAYJRwWGaQCrAAANAAYJRwWGaQCrAAAAAA==.Babymuffins:BAABLgAECn8pAAIMAAgJqB8ZIwB5AgAMAAgJqB8ZIwB5AgAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAABLgAECn8UAAINAAgJYwlKSAATAQANAAgJYwlKSAATAQAAAA==.Beklee:BAAALgADCgYJBgAAAA==.Belanda:BAAALgAECgYJDAAAAA==.Belgord:BAAALgAECgYJEwAAAA==.Belin:BAAALgADCgkJFgAAAA==.Bellyn:BAAALgAECggJCgAAAA==.Belmond:BAAALgAECgQJCAAAAA==.Belzac:BAAALgAECgMJAwAAAA==.Bemuse:BAAALgADCgcJDAAAAA==.',
Bl='Blackmill:BAABLgAECn8UAAIOAAgJZBohBQAuAgAOAAgJZBohBQAuAgAAAA==.Blayrog:BAABLgAECn8qAAICAAgJuBTabgCcAQACAAgJuBTabgCcAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8vAAMPAAkJGBitDQAOAgAPAAkJzRetDQAOAgABAAYJ/RDSUQBiAQABLgAFFAcJGQAQADEUAA==.Bobamood:BAAALgAFFAIJAwAAAA==.Bobbijoe:BAAALgAECgEJAQAAAA==.Bobbyknocker:BAAALgAECgcJCAAAAA==.Bolf:BAABLgAECn8kAAMRAAcJoQ4zAwBEAQARAAcJLAwzAwBEAQASAAYJ9AueEQDwAAAAAA==.Boneharnen:BAAALgAECgYJDAAAAA==.Boombaaby:BAABLgAECn8wAAIFAAkJsg35XACPAQAFAAkJsg35XACPAQAAAA==.Boomkittie:BAAALgADCgYJBgAAAA==.Bootzee:BAABLgAECn8gAAIJAAcJbxu3KAAbAgAJAAcJbxu3KAAbAgAAAA==.',
Br='Brewglaive:BAAALgAECgEJAwAAAA==.Brewsli:BAAALgAECgMJAwAAAA==.Britishchick:BAAALgAECgYJBgABLgAECgkJKQATALgcAA==.Brookenoel:BAABLgAECn8nAAIQAAkJ+AgBMABfAQAQAAkJ+AgBMABfAQAAAA==.Brunhilian:BAAALgAECgYJDwAAAA==.',
Bs='Bsê:BAAALgAECgIJAgAAAA==.',
Bu='Buckmaster:BAAALgAECgUJEAAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAABLgAECn8pAAIBAAkJfgf2RwAlAQABAAkJfgf2RwAlAQAAAA==.Calada:BAABLgAECn8jAAIHAAgJvgLlCQCSAAAHAAgJvgLlCQCSAAAAAA==.Callypso:BAAALgAECgYJBgABLgAECgkJJAAKAAgOAA==.Carbion:BAAALgADCgkJCQAAAA==.Carnan:BAAALgADCgEJAQAAAA==.Cassandraa:BAAALgAFFAIJAQAAAA==.',
Ce='Cedarnia:BAAALgADCggJDwAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAgAGAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8eAAIJAAkJOxbGHwBRAgAJAAkJOxbGHwBRAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJDgAAAA==.',
Co='Corrynn:BAAALgAECgcJEgAAAA==.',
Cr='Cribbage:BAACLgAFFH8LAAIUAAMJ2B5NFwDhAAAUAAMJ2B5NFwDhAAAuAAQKfykAAxQACQlJImwFAMECABQACQlJImwFAMECAA8AAQnMGrBtAEYAAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgAECgEJAgAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgUJEwAAAA==.',
Cv='Cvaluenigma:BAAALgAECgEJAQAAAA==.',
Cy='Cynosure:BAABLgAECn8yAAIRAAkJvRkdEQAgAgARAAkJvRkdEQAgAgAAAA==.Cytronsneak:BAABLgAECn8UAAIRAAYJEw71LwAgAQARAAYJEw71LwAgAQAAAA==.',
Da='Dabb:BAAALgAECgIJAgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgUJDQAAAA==.Daela:BAAALgADCgYJBgAAAA==.Daliå:BAAALgAECgEJAQAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8kAAIIAAkJdgyvVwCWAQAIAAkJdgyvVwCWAQAAAA==.Darkheaven:BAABLgAECn8eAAIMAAkJagoIdQCEAQAMAAkJagoIdQCEAQAAAA==.Darkkanaka:BAAALgADCgEJAwAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgMJAwAAAA==.Dazarek:BAABLgAECn8qAAIVAAkJQAagKwD9AAAVAAkJQAagKwD9AAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Deathrazor:BAAALgADCgUJBQAAAA==.Demium:BAACLgAFFH8aAAIWAAcJOBhrKwB6AQAWAAcJOBhrKwB6AQAuAAQKfykAAhYACAmMIsMeAFwCABYACAmMIsMeAFwCAAEuAAQKBQkKAAYAAAAA.Demonkanaka:BAAALgADCgMJBgAAAA==.Denae:BAAALgAECgEJAQABLgAECgYJCwAGAAAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgAECgUJBQAAAA==.Devinetoro:BAABLgAECn8vAAIMAAkJVQhUhgBjAQAMAAkJVQhUhgBjAQAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAIXAAkJGRcmLAD/AQAXAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn84AAQYAAkJeBoyAwBsAgAYAAkJeBoyAwBsAgAZAAQJTRIzLQCBAAAaAAMJLQYieQBxAAAAAA==.',
Dk='Dklunar:BAABLgAFFH8HAAIDAAQJhQMRywCYAAADAAQJhQMRywCYAAABLgAFFAcJFAAXAHgTAA==.',
Do='Doree:BAAALgAECgUJBQAAAA==.Dotdotoops:BAAALgAECgEJAQAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAYJIQAbAI4TAA==.Dreadsofdeth:BAABLgAECn8VAAICAAYJixh1ngCZAQACAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJEAAAAA==.Drklhtkanaka:BAAALgAECgEJAgAAAA==.Drunkenbilly:BAAALgAECgIJAgAAAA==.Drustone:BAAALgADCgEJAQAAAA==.',
Dw='Dwangler:BAAALgAECgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8yAAIIAAgJBBI4VgCaAQAIAAgJBBI4VgCaAQAAAA==.',
Ea='Earthroot:BAAALgADCgEJAQAAAA==.',
Eh='Ehtar:BAAALgAECgYJBgABLgAFFAcJGQAQADEUAA==.',
Ei='Einheri:BAABLgAECn84AAIBAAkJRh1wAgC+AQABAAkJRh1wAgC+AQAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgAECgYJCAAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8UAAIRAAMJyiBkIgASAQARAAMJyiBkIgASAQAuAAQKfywAAhEACQkvGmwPADYCABEACQkvGmwPADYCAAAA.Enoira:BAAALgAECgEJAgAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAABLgAECn8mAAILAAgJ6BM5AgBqAQALAAgJ6BM5AgBqAQAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Et='Ethel:BAAALgAECgEJAQAAAA==.',
Ev='Evillizard:BAABLgAECn8XAAIaAAgJ2wpiQAAoAQAaAAgJ2wpiQAAoAQAAAA==.',
Ex='Exhumer:BAABLgAECn8nAAIMAAkJoSV7DgDyAgAMAAkJoSV7DgDyAgAAAA==.',
Fa='Faffard:BAABLgAECn8fAAIFAAgJRg/RgwA3AQAFAAgJRg/RgwA3AQABLgAECgkJOQAcAEUJAA==.Fame:BAAALgAFFAEJAQABLgAFFAYJGAAaAPkXAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgUJBgAAAA==.',
Fe='Fearbilly:BAAALgAECgUJCQAAAA==.Felbilly:BAAALgAECgIJAgAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAABLgAECn8oAAMXAAgJUwSdCQCoAAAXAAgJUwSdCQCoAAAdAAEJrAHvqgASAAAAAA==.',
Fi='Fily:BAAALgAECgYJBgAAAA==.',
Fl='Flap:BAACLgAFFH8YAAIaAAYJ+RclIQBXAQAaAAYJ+RclIQBXAQAuAAQKfyMAAxoACQmOHSQCAI4BABoACQmOHSQCAI4BABgAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fu='Funenix:BAAALgADCggJDQAAAA==.Furbalkanaka:BAAALgADCgEJAQAAAA==.',
Fy='Fystie:BAABLgAECn8yAAMXAAgJjhbmAwByAQAXAAgJjhbmAwByAQAdAAUJXw6mUQDHAAABLgAECgkJOQAcAEUJAA==.',
Ga='Galacticfox:BAAALgAECgIJAgAAAA==.Galpally:BAABLgAECn8uAAIMAAcJcBc+BgCfAQAMAAcJcBc+BgCfAQAAAA==.Ganzar:BAAALgADCgMJBAAAAA==.Garin:BAAALgAECgUJBgAAAA==.',
Ge='Genma:BAAALgAECgQJBAAAAA==.Gennic:BAAALgADCgcJBwAAAA==.Gettinskins:BAAALgAECgMJAwAAAA==.',
Gh='Ghenghiskhan:BAAALgAECgIJAQAAAA==.',
Gi='Gishongar:BAAALgAECgkJCgAAAA==.',
Gl='Glorak:BAABLgAECn8nAAIFAAcJdgj4igApAQAFAAcJdgj4igApAQAAAA==.',
Gr='Grashen:BAABLgAECn8oAAIJAAgJ0hlEKQAYAgAJAAgJ0hlEKQAYAgAAAA==.Gravorik:BAABLgAFFH8MAAMLAAMJPAfMBgBlAAALAAMJXgXMBgBlAAAMAAEJbwfQuQBDAAAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDwAAAA==.',
Gs='Gsm:BAABLgAECn9GAAINAAkJShsIDwB/AgANAAkJShsIDwB/AgAAAA==.',
Gu='Gulritz:BAAALgAECgIJAgAAAA==.Gulrum:BAAALgADCgEJAQAAAA==.Gurlyman:BAAALgAECgYJDgAAAA==.',
Ha='Haikara:BAAALgADCgMJAwAAAA==.Hante:BAAALgADCgcJEAAAAA==.Hartmonster:BAAALgAECgQJCAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMFAAcJIQVmbQAfAQAFAAYJ0gVmbQAfAQAeAAEJrwF/RgAbAAAAAA==.Hideous:BAAALgAECgQJCgAAAA==.Hikarí:BAAALgAECgMJAwAAAA==.',
Ho='Hobuul:BAAALgADCgcJCwAAAA==.Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoofnstien:BAAALgADCgYJBgAAAA==.Hoompukka:BAAALgAECgYJEwAAAA==.Hotspur:BAAALgAECgMJAwABLgAECgkJKQAXAEUVAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ia='Iaanditos:BAAALgADCgYJBgAAAA==.',
Ig='Ignath:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilisselia:BAAALgADCgcJBwAAAA==.Ilokana:BAAALgAECgUJEQAAAA==.Ilostmybible:BAAALgAECgMJBQAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAABLgAECn8ZAAIBAAYJXxOPQgA7AQABAAYJXxOPQgA7AQAAAA==.',
It='Itzbarney:BAAALgAECggJEwAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacsknight:BAAALgAECgUJBwAAAA==.Jacspally:BAABLgAECn8rAAMMAAkJTh4RAwA9AgAMAAkJTh4RAwA9AgAfAAEJ0AP3nQAiAAAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8jAAITAAkJkSAjBADZAgATAAkJkSAjBADZAgAAAA==.Jarlath:BAAALgAECgQJBAAAAA==.',
Je='Jebra:BAABLgAECn83AAMdAAkJ8xQ7FwATAgAdAAkJ8xQ7FwATAgATAAEJAAQbjQARAAAAAA==.Jellexy:BAABLgAECn8xAAICAAgJ0QWQEQDrAAACAAgJ0QWQEQDrAAAAAA==.',
Ji='Jimlahey:BAAALgAECgMJAwABLgAFFAUJGQACADEfAA==.',
Jo='Johnnybone:BAAALgAECgUJBQAAAA==.Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8iAAIKAAUJDRd3IABrAQAKAAUJDRd3IABrAQAuAAQKfzIAAgoACQn5HEoRAJYCAAoACQn5HEoRAJYCAAAA.Jonnyfive:BAABLgAECn8WAAIMAAYJBxH4sgAbAQAMAAYJBxH4sgAbAQAAAA==.',
['Jó']='Jósepha:BAAALgADCgQJBAAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIFAAkJ6hfpLwAdAgAFAAkJ6hfpLwAdAgAAAA==.Kaisa:BAAALgAECgEJAgAAAA==.Kalimthor:BAAALgADCgEJAQAAAA==.Kanakafist:BAAALgAECgEJAQAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAABLgAECn8fAAIMAAkJ+RN8VgDHAQAMAAkJ+RN8VgDHAQAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8yAAMFAAkJfR+tCAAzAgAFAAkJfR+tCAAzAgAeAAYJEw3CCgBuAQAuAAQKf0EAAx4ACQkiJo8CAIkDAB4ACQkYIo8CAIkDAAUACQkiJiIHACUDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgUJBQAAAA==.Keheo:BAAALgAECgQJCwAAAA==.',
Kh='Khandragho:BAAALgAECgYJBgAAAA==.Khaza:BAAALgAECgUJBQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kiri:BAAALgAECgMJBAABLgAECgkJNQAgAEMRAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn9PAAIEAAkJGSKQAQAdAwAEAAkJGSKQAQAdAwAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIfAAkJbRfBJgD0AQAfAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgUJDgAAAA==.Kruger:BAABLgAECn8jAAIIAAcJ+geMoQD8AAAIAAcJ+geMoQD8AAAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.Krzyhayn:BAAALgADCgUJBgAAAA==.Krzykanaka:BAAALgADCgIJBAAAAA==.',
Kt='Ktanna:BAABLgAECn8XAAIhAAcJaAjPNQDlAAAhAAcJaAjPNQDlAAAAAA==.',
Ku='Kublakhan:BAAALgAECgkJEAAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAcJMAALACscAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8gAAIJAAkJixwPKgAUAgAJAAkJixwPKgAUAgAAAA==.Lapras:BAEBLgAFFH8OAAMaAAUJeyaQFgC4AQAaAAUJeyaQFgC4AQAYAAEJ6iULCwBxAAAAAA==.Lateralus:BAABLgAECn8wAAIMAAkJvhnFKABfAgAMAAkJvhnFKABfAgAAAA==.Laureli:BAABLgAECn8rAAIBAAgJSgY2CADnAAABAAgJSgY2CADnAAAAAA==.',
Le='Leeta:BAABLgAECn8pAAITAAkJuBzZCQBLAgATAAkJuBzZCQBLAgAAAA==.Legendx:BAAALgADCgUJBwAAAA==.Letholdus:BAABLgAECn8dAAIEAAkJOBf+AADiAQAEAAkJOBf+AADiAQAAAA==.',
Li='Lightningg:BAABLgAECn8fAAIYAAkJAAyyCQCLAQAYAAkJAAyyCQCLAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgABLgAFFAQJDgACAOwYAA==.',
Lo='Loahavemercy:BAAALgAECgEJAQAAAA==.Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAABLgAECn8UAAILAAYJsgQcNwCDAAALAAYJsgQcNwCDAAAAAA==.Losoz:BAAALgAECgEJAgAAAA==.',
Lu='Lucariel:BAABLgAECn8hAAIDAAkJjRwZGAC2AgADAAkJjRwZGAC2AgAAAA==.Lusilsandrus:BAAALgAECgYJEwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAABLgAFFH8KAAIJAAQJphGPGQC/AAAJAAQJphGPGQC/AAAAAA==.Magusbilly:BAAALgAECgQJBQAAAA==.Mahoutsukai:BAABLgAECn8gAAICAAkJKQP5rQAlAQACAAkJKQP5rQAlAQAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8pAAINAAkJHAjtSQANAQANAAkJHAjtSQANAQAAAA==.',
Me='Mechaknight:BAAALgAECgUJCgAAAA==.',
Mi='Mildrik:BAABLgAECn8fAAIBAAkJCQrZMQCFAQABAAkJCQrZMQCFAQAAAA==.Miracledh:BAABLgAECn8aAAIhAAgJkiVXBgDSAgAhAAgJkiVXBgDSAgAAAA==.Mirkdrak:BAABLgAECn8jAAMaAAcJrguAUgDlAAAaAAcJrguAUgDlAAAYAAMJyQJmNgBjAAAAAA==.Mishach:BAAALgAECgQJBAABLgAECggJAgAGAAAAAA==.Misheard:BAACLgAFFH8DAAIWAAIJmBGOmQBCAAAWAAIJmBGOmQBCAAAuAAQKfzoAAhYACQnKIPoUAJsCABYACQnKIPoUAJsCAAAA.Misjudged:BAABLgAECn8YAAQaAAgJexO1LwB5AQAaAAgJexO1LwB5AQAYAAQJhw0dKQDWAAAZAAIJghjmOwA0AAAAAA==.Missus:BAAALgAFFAMJAwAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgQJBQAAAA==.Mizzen:BAABLgAECn8sAAMiAAkJPSGuBgDfAgAiAAkJPSGuBgDfAgAjAAEJawRVpwAdAAABLgAFFAcJGQAQADEUAA==.',
Mo='Mohtavius:BAABLgAECn83AAIUAAkJlhlNCgBMAgAUAAkJlhlNCgBMAgAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn85AAIcAAkJRQmxEQAtAQAcAAkJRQmxEQAtAQAAAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Ms='Msbehavin:BAAALgAECgEJAgAAAA==.',
Mu='Mulnier:BAAALgADCgkJCgAAAA==.Munkìe:BAAALgAECgUJDQABLgAECgkJRgANAEobAA==.Muura:BAACLgAFFH8JAAIDAAMJXwS+PwCuAAADAAMJXwS+PwCuAAAuAAQKfyEAAgMACQkQDf+nACABAAMACQkQDf+nACABAAAA.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJEgAAAA==.',
Na='Nabsta:BAAALgAECgEJAQAAAA==.Nakavelli:BAAALgAECgEJAQAAAA==.Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn80AAMJAAkJLB+gDgDfAgAJAAkJLB+gDgDfAgAkAAEJRhOIDAA7AAAAAA==.Nattal:BAAALgADCgUJBQAAAA==.Nausica:BAAALgAFFAIJAQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJDAAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAgJMQAZAOIdAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Ot='Otwin:BAABLgAECn8aAAMJAAYJ7hWbSwCCAQAJAAYJ7hWbSwCCAQANAAEJnAfQtgAlAAAAAA==.',
Pa='Pahuum:BAAALgAECgYJEwAAAA==.Paimon:BAABLgAECn8hAAILAAgJaByCCgAhAgALAAgJaByCCgAhAgABLgAFFAYJGAAaAPkXAA==.Paintrainn:BAABLgAECn8XAAIJAAgJdgGsnQCVAAAJAAgJdgGsnQCVAAAAAA==.Palewhiteman:BAABLgAECn8hAAIfAAgJ5hm3GwAmAgAfAAgJ5hm3GwAmAgAAAA==.Palleigh:BAABLgAECn8vAAIfAAkJEhH3AwBSAQAfAAkJEhH3AwBSAQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Parodoxx:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8pAAIXAAkJRRUCLQD0AQAXAAkJRRUCLQD0AQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8kAAIFAAkJTxmRKAA9AgAFAAkJTxmRKAA9AgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Pl='Plague:BAABLgAFFH8LAAIDAAYJjBjpDgCnAQADAAYJjBjpDgCnAQAAAA==.',
Po='Poondor:BAABLgAECn8aAAIfAAkJRRSsGwAmAgAfAAkJRRSsGwAmAgAAAA==.Porsch:BAAALgADCgIJAgAAAA==.',
Pr='Praylorswíft:BAAALgAECgMJAwABLgAECgkJIAACAJ4PAA==.Predaturd:BAAALgAECggJBQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Py='Pyxis:BAAALgADCgEJAQAAAA==.',
Qi='Qindere:BAABLgAECn8lAAICAAkJEAyQBwCBAQACAAkJEAyQBwCBAQAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn9GAAIFAAkJPhquIwBUAgAFAAkJPhquIwBUAgAAAA==.Rakshaman:BAABLgAECn8cAAIJAAgJ2AoVDADhAAAJAAgJ2AoVDADhAAAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgYJDAAAAA==.',
Re='Reihino:BAAALgAECgcJDAAAAA==.Resbak:BAABLgAECn8ZAAIdAAgJ3w7dLQBsAQAdAAgJ3w7dLQBsAQAAAA==.Resiaus:BAABLgAECn89AAIZAAkJyRyZBADgAgAZAAkJyRyZBADgAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECggJEAAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Robinho:BAAALgAECgcJDQAAAA==.Rocketabu:BAAALgAECgQJCwAAAA==.Roctheist:BAABLgAECn8UAAMQAAYJEAbHSAC8AAAQAAYJEAbHSAC8AAAHAAYJEwZgTwCjAAAAAA==.Rocthoeb:BAABLgAECn80AAIUAAkJxRH/EQDoAQAUAAkJxRH/EQDoAQAAAA==.Rodnag:BAAALgADCgEJAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.Rokstedy:BAAALgAECgEJAQAAAA==.',
Ry='Ry:BAABLgAECn8qAAMlAAkJOSPtAQAWAwAlAAkJOSPtAQAWAwAXAAEJ8ASi+gAaAAAAAA==.',
Sa='Saeris:BAAALgAECgUJBwAAAA==.Saintalpha:BAEALgAECgEJAQABLgAECggJFQAgAJkTAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFQAgAJkTAA==.Saintkhal:BAEALgAECgQJDQABLgAECggJFQAgAJkTAA==.Saintmedicus:BAEBLgAECn8VAAMgAAgJmRP/NwAzAQAgAAUJZBf/NwAzAQAQAAMJ0w3jYQCSAAAAAA==.Saintshammy:BAABLgAFFH8FAAIJAAMJWxXpSgDFAAAJAAMJWxXpSgDFAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Saki:BAAALgADCgUJBQAAAA==.Sanctor:BAABLgAECn8dAAIfAAcJeyJ0EgB/AgAfAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Sangairee:BAAALgAECgYJBgAAAA==.Saraya:BAABLgAECn8XAAIfAAkJFhekHgANAgAfAAkJFhekHgANAgAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8jAAIgAAkJYh2RCADsAgAgAAkJYh2RCADsAgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shanoodles:BAAALgAECgUJCQABLgAECgYJBgAGAAAAAA==.Shibaryotaro:BAAALgAECgEJAQAAAA==.Shiftee:BAAALgAECgQJBAABLgAECgcJHAAFABsWAA==.Shinstabber:BAABLgAECn8jAAIVAAkJARTQEwDWAQAVAAkJARTQEwDWAQAAAA==.Shivantice:BAAALgAECgcJCAAAAA==.Shivantis:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Shruggie:BAABLgAECn9AAAMhAAkJ0hhaAQA2AgAhAAkJ0hhaAQA2AgAWAAQJDAPC/QBOAAAAAA==.',
Si='Silven:BAAALgAECgYJDgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8aAAIKAAkJpxn6EgCEAgAKAAkJpxn6EgCEAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8cAAIFAAcJGxZxLwD0AQAFAAcJGxZxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgAECgYJCgAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8tAAMeAAkJuwenEwAmAQAbAAgJKATRLQA3AQAeAAkJnAenEwAmAQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAJADYRAA==.Starlie:BAAALgAECgUJDgAAAA==.Stormstrike:BAAALgAECgcJBgAAAA==.Stratacaster:BAABLgAECn8YAAIIAAcJ0QKG1gCpAAAIAAcJ0QKG1gCpAAAAAA==.Strawberry:BAAALgAFFAEJAQAAAA==.Stuckinwell:BAACLgAFFH8FAAMIAAIJkBjuNQCnAAAIAAIJGBDuNQCnAAAcAAEJlBbVJgBHAAAuAAQKfxsAAwgACQn6GsEzAD0CAAgACAnpFsEzAD0CABwABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAIXAAIJhh6QFQC3AAAXAAIJhh6QFQC3AAABLgAFFAgJMQAZAOIdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDwABLgAECgkJXwAVAJUZAA==.Synfyl:BAEALgAFFAIJAgABLgAFFAIJCAAmAGQHAA==.Synpathi:BAEALgADCgEJAQABLgAFFAIJCAAmAGQHAA==.Synsyn:BAECLgAFFH8IAAMmAAIJZAcYBgCKAAAmAAIJZAcYBgCKAAAIAAEJVgDB2AAjAAAuAAQKf1YAAyYACAkoFacNAIIBACYACAkoFacNAIIBAAgABgnQCXuyAOAAAAAA.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgMJAgAAAA==.Taílorswift:BAABLgAECn8gAAICAAkJng+giABmAQACAAkJng+giABmAQAAAA==.',
Te='Teanfists:BAAALgAECgYJCgAAAA==.Tearstain:BAAALgADCgcJBwAAAA==.Temna:BAABLgAECn87AAIMAAkJBiT5BQBDAwAMAAkJBiT5BQBDAwAAAA==.Tenari:BAAALgAECggJDwAAAA==.Tevye:BAAALgADCgYJBgAAAA==.',
Th='Theel:BAABLgAECn8qAAIFAAcJgR6BBADuAQAFAAcJgR6BBADuAQAAAA==.Theruss:BAAALgAECgEJAQAAAA==.Thespaniard:BAABLgAECn8fAAIQAAkJqxjzFAAmAgAQAAkJqxjzFAAmAgAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAABLgAECn8WAAITAAgJlQl4MADpAAATAAgJlQl4MADpAAABLgAFFAEJAQAGAAAAAA==.Tinbasher:BAAALgAECgYJDQAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Toast:BAAALgADCgEJAQAAAA==.Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAABLgAECn8eAAMXAAkJ7gnFSQBnAQAXAAkJ7gnFSQBnAQAdAAEJ5QxFjgAyAAAAAA==.Tricky:BAABLgAECn8UAAICAAcJag+IHACSAAACAAcJag+IHACSAAAAAA==.Triviousox:BAABLgAECn8aAAIMAAcJwhD/jwBSAQAMAAcJwhD/jwBSAQAAAA==.Tryxx:BAAALgADCgUJBQAAAA==.Trêehugger:BAAALgAECgEJAQABLgAECgYJBgAGAAAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJFAABLgAFFAYJEgAnAPMcAA==.Twotvmage:BAABLgAECn8wAAMCAAkJex2qKQB0AgACAAkJex2qKQB0AgAnAAEJIA1+GAAuAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Uneedarez:BAAALgAECgQJBAAAAA==.Unglued:BAAALgAECgYJBgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJDQABLgAECgkJNwAIAA8cAA==.',
Up='Uplift:BAABLgAFFH8FAAIiAAQJXRhDEgAqAQAiAAQJXRhDEgAqAQABLgAFFAgJHgACAJsbAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Ut='Uttrsdeek:BAABLgAFFH8IAAIDAAMJ2hK3MQDYAAADAAMJ2hK3MQDYAAAAAA==.',
Va='Vale:BAAALgAECggJCAAAAA==.Valkky:BAABLgAECn84AAMoAAkJXRbwBwD8AQAoAAkJsxXwBwD8AQAWAAQJOA0VowDOAAAAAA==.Valky:BAAALgAECgEJAQABLgAECgkJOAAoAF0WAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn81AAQgAAkJQxGwHgDZAQAgAAkJ9A2wHgDZAQAHAAcJiw9HNgAnAQAQAAIJ2wRdfQBDAAAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vanity:BAAALgAECgUJBQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECggJEAABLgAECgkJNQAgAEMRAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn85AAIFAAkJbx4IEQDIAgAFAAkJbx4IEQDIAgAAAA==.Versipelliz:BAAALgADCgEJAQAAAA==.Vessna:BAABLgAECn8jAAICAAcJTQd+3gDdAAACAAcJTQd+3gDdAAABLgAECgcJIwAaAK4LAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAABLgAECn8sAAIlAAgJ8CJ6AAB6AgAlAAgJ8CJ6AAB6AgAAAA==.',
Vm='Vmro:BAAALgADCgYJFgAAAA==.',
Vo='Voras:BAAALgAECgYJEQAAAA==.Vorttex:BAAALgAECgUJEQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJLAAaAGcfAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8pAAIoAAkJixlHBwAQAgAoAAkJixlHBwAQAgAAAA==.',
Wh='Whiskeyrick:BAAALgAECgcJDgAAAA==.',
Wi='Wildkanaka:BAAALgAECgEJAQAAAA==.Winters:BAAALgAECgEJAQAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIQAAgJ4RsHEQB4AgAQAAgJ4RsHEQB4AgAAAA==.',
Xi='Xivago:BAAALgAECgUJCQAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAACLgAFFH8HAAIbAAMJcQj1IgDBAAAbAAMJcQj1IgDBAAAuAAQKfxYAAxsACAkDDhElAHUBABsACAkDDhElAHUBAB4ABAmABINqAJQAAAAA.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yo='Yoshino:BAAALgAECgUJBgABLgAECgYJIgACALUKAA==.',
Yu='Yuzuriha:BAAALgAECgYJDwAAAA==.',
Za='Zalamandr:BAAALgAECgEJAwAAAA==.Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgAFFAEJAQAAAA==.',
Zo='Zophier:BAAALgAECgQJBwAAAA==.Zouk:BAAALgAECgUJCgAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAABLgAECn8YAAIeAAcJhwzQFQALAQAeAAcJhwzQFQALAQAAAA==.',
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
