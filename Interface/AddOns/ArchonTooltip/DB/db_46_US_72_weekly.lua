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

local lookup = {'Warrior-Fury','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Rogue-Outlaw','Druid-Guardian','Priest-Holy','Warrior-Protection','DeathKnight-Blood','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Warlock-Destruction','Druid-Balance','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement','Druid-Feral','Warlock-Affliction','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ab='Abugarcia:BAAALgAECgUJBwAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akiryss:BAABLgAECn8bAAIBAAkJNBLKBQDiAAABAAkJNBLKBQDiAAAAAA==.Akusenshi:BAABLgAECn8UAAIBAAcJOxBdOgBcAQABAAcJOxBdOgBcAQAAAA==.',
Al='Alarr:BAAALgAECgYJBwABLgAFFAQJDgACAOwYAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alenthia:BAAALgADCgEJAQAAAA==.Alethrix:BAABLgAECn8hAAMDAAgJ0xgQQQD/AQADAAgJ0xgQQQD/AQAEAAEJxxCIOgAzAAAAAA==.Alexi:BAAALgADCgkJCwAAAA==.Alivis:BAEALgAECgQJBwABLgAFFAMJBQAFAK0VAA==.Alzith:BAAALgAECgQJBQABLgAECgkJIQADAI0cAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAkJRwAHAFclAA==.Animocity:BAAALgAECgQJBgAAAA==.',
Ap='Apexalpha:BAAALgAECgQJCAAAAA==.Appletinni:BAAALgAECgIJAgAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Arius:BAAALgADCgUJBQAAAA==.Armster:BAAALgAECgcJCgAAAA==.Arold:BAABLgAECn8lAAIIAAkJRhaPNAAHAgAIAAkJRhaPNAAHAgAAAA==.',
As='Asylia:BAACLgAFFH8KAAIJAAQJNhGCCQA5AQAJAAQJNhGCCQA5AQAuAAQKfxcAAgkACAlLGy4hABcCAAkACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8kAAIKAAkJCQ57QQBoAQAKAAkJCQ57QQBoAQAAAA==.',
Au='Aulendil:BAAALgAECgEJAQAAAA==.Aurelliae:BAABLgAECn8WAAIFAAgJtBWSVACmAQAFAAgJtBWSVACmAQAAAA==.',
Av='Avesiren:BAABLgAECn8xAAILAAkJTBXSAADhAQALAAkJTBXSAADhAQAAAA==.',
Ax='Axxion:BAAALgADCgYJBgAAAA==.',
Ay='Ayidá:BAAALgAECggJEwAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAABLgAECn8aAAIMAAkJpgjvCQAIAQAMAAkJpgjvCQAIAQAAAA==.Babymamaa:BAABLgAECn8VAAINAAYJRwWGaQCrAAANAAYJRwWGaQCrAAAAAA==.Babymuffins:BAABLgAECn8pAAIMAAgJqB8ZIwB5AgAMAAgJqB8ZIwB5AgAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAABLgAECn8UAAINAAgJYwlKSAATAQANAAgJYwlKSAATAQAAAA==.Beklee:BAAALgADCgYJBgAAAA==.Belanda:BAAALgAECgYJDAAAAA==.Belgord:BAAALgAECgYJEwAAAA==.Belin:BAAALgADCgkJFgAAAA==.Bellyn:BAAALgAECggJCAAAAA==.Belmond:BAAALgAECgQJCAAAAA==.Belzac:BAAALgAECgMJAwAAAA==.Bemuse:BAAALgADCgcJDAAAAA==.',
Bl='Blackmill:BAABLgAECn8UAAIOAAgJZBohBQAuAgAOAAgJZBohBQAuAgAAAA==.Blayrog:BAABLgAECn8qAAICAAgJuBTabgCcAQACAAgJuBTabgCcAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8vAAMPAAkJGBitDQAOAgAPAAkJzRetDQAOAgABAAYJ/RDSUQBiAQABLgAFFAcJGQAQADEUAA==.Bobamood:BAAALgAFFAIJAwAAAA==.Bobbyknocker:BAAALgAECgcJCAAAAA==.Bolf:BAABLgAECn8kAAMRAAcJ5w74AQBWAQARAAcJcQz4AQBWAQASAAYJ9AueEQDwAAAAAA==.Boneharnen:BAAALgAECgYJDAAAAA==.Boombaaby:BAABLgAECn8wAAIFAAkJrg35XACPAQAFAAkJrg35XACPAQAAAA==.Boomkittie:BAAALgADCgYJBgAAAA==.Bootzee:BAABLgAECn8gAAIJAAcJbxu3KAAbAgAJAAcJbxu3KAAbAgAAAA==.',
Br='Brewglaive:BAAALgAECgEJAwAAAA==.Brewsli:BAAALgAECgMJAwAAAA==.Britishchick:BAAALgAECgYJBgABLgAECgkJKQATALgcAA==.Brookenoel:BAABLgAECn8nAAIQAAkJ+AgBMABfAQAQAAkJ+AgBMABfAQAAAA==.Brunhilian:BAAALgAECgYJDwAAAA==.',
Bs='Bsê:BAAALgAECgIJAgAAAA==.',
Bu='Buckmaster:BAAALgAECgUJDQAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAABLgAECn8pAAIBAAkJfAf2RwAlAQABAAkJfAf2RwAlAQAAAA==.Calada:BAABLgAECn8iAAIUAAcJ9AKzBgCaAAAUAAcJ9AKzBgCaAAAAAA==.Callypso:BAAALgAECgYJBgABLgAECgkJJAAKAAkOAA==.Carbion:BAAALgADCgkJCQAAAA==.Cassandraa:BAAALgAFFAEJAQAAAA==.',
Ce='Cedarnia:BAAALgADCggJDwAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAgAGAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8eAAIJAAkJOxbGHwBRAgAJAAkJOxbGHwBRAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJDgAAAA==.',
Ck='Ckrazykanaka:BAAALgADCgEJAgAAAA==.',
Co='Corrynn:BAAALgAECgcJEgAAAA==.',
Cr='Cribbage:BAACLgAFFH8LAAIVAAMJ2B5NFwDhAAAVAAMJ2B5NFwDhAAAuAAQKfykAAxUACQlJImwFAMECABUACQlJImwFAMECAA8AAQnMGrBtAEYAAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgAECgEJAQAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgUJEwAAAA==.',
Cv='Cvaluenigma:BAAALgAECgEJAQAAAA==.',
Cy='Cynosure:BAABLgAECn8yAAIRAAkJvRkdEQAgAgARAAkJvRkdEQAgAgAAAA==.Cytronsneak:BAABLgAECn8UAAIRAAYJEw71LwAgAQARAAYJEw71LwAgAQAAAA==.',
Da='Dabb:BAAALgAECgIJAgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgUJDQAAAA==.Daela:BAAALgADCgYJBgAAAA==.Daliå:BAAALgAECgEJAQAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8kAAIIAAkJdgyvVwCWAQAIAAkJdgyvVwCWAQAAAA==.Darkheaven:BAABLgAECn8eAAIMAAkJagoIdQCEAQAMAAkJagoIdQCEAQAAAA==.Darkkanaka:BAAALgADCgEJAgAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgMJAwAAAA==.Dazarek:BAABLgAECn8pAAIWAAkJPAagKwD9AAAWAAkJPAagKwD9AAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8aAAIXAAcJYhlrKwB6AQAXAAcJYhlrKwB6AQAuAAQKfykAAhcACAmMIsMeAFwCABcACAmMIsMeAFwCAAEuAAQKBQkKAAYAAAAA.Demonkanaka:BAAALgADCgMJBgAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgAECgUJBQAAAA==.Devinetoro:BAABLgAECn8vAAIMAAkJVQhUhgBjAQAMAAkJVQhUhgBjAQAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAIYAAkJGRcmLAD/AQAYAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn84AAQZAAkJfhoyAwBsAgAZAAkJfhoyAwBsAgAaAAQJTRIzLQCBAAAbAAMJLQYieQBxAAAAAA==.',
Dk='Dklunar:BAABLgAFFH8HAAIDAAQJhQMRywCYAAADAAQJhQMRywCYAAABLgAFFAYJEwAYADwYAA==.',
Do='Doree:BAAALgAECgUJBQAAAA==.Dotdotoops:BAAALgAECgEJAQAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAYJIQAcAI4TAA==.Dreadsofdeth:BAABLgAECn8VAAICAAYJixh1ngCZAQACAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJEAAAAA==.Drklhtkanaka:BAAALgAECgEJAgAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.Drustone:BAAALgADCgEJAQAAAA==.',
Dw='Dwangler:BAAALgAECgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8yAAIIAAgJBBI4VgCaAQAIAAgJBBI4VgCaAQAAAA==.',
Ea='Earthroot:BAAALgADCgEJAQAAAA==.',
Eh='Ehtar:BAAALgAECgYJBgABLgAFFAcJGQAQADEUAA==.',
Ei='Einheri:BAABLgAECn8vAAIBAAkJyxzzEQBkAgABAAkJyxzzEQBkAgAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgAECgYJCAAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8UAAIRAAMJyiBkIgASAQARAAMJyiBkIgASAQAuAAQKfywAAhEACQkvGmwPADYCABEACQkvGmwPADYCAAAA.Enoira:BAAALgAECgEJAgAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAABLgAECn8lAAILAAcJnBW6AQBNAQALAAcJnBW6AQBNAQAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Et='Ethel:BAAALgAECgEJAQAAAA==.',
Ev='Evillizard:BAABLgAECn8XAAIbAAgJ2wpiQAAoAQAbAAgJ2wpiQAAoAQAAAA==.',
Ex='Exhumer:BAABLgAECn8nAAIMAAkJoCV7DgDyAgAMAAkJoCV7DgDyAgAAAA==.',
Fa='Faffard:BAABLgAECn8eAAIFAAcJEA/RgwA3AQAFAAcJEA/RgwA3AQABLgAECgkJOQAdAEUJAA==.Fame:BAAALgAFFAEJAQABLgAFFAYJGAAbAPkXAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgUJBgAAAA==.',
Fe='Fearbilly:BAAALgAECgUJCQAAAA==.Felbilly:BAAALgAECgEJAQAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAABLgAECn8nAAMYAAcJZwQgBwCfAAAYAAcJZwQgBwCfAAAeAAEJrAHvqgASAAAAAA==.',
Fl='Flap:BAACLgAFFH8YAAIbAAYJ+RclIQBXAQAbAAYJ+RclIQBXAQAuAAQKfx4AAxsACQntG24cAOQBABsACQntG24cAOQBABkAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fu='Funenix:BAAALgADCgUJBQAAAA==.Furbalkanaka:BAAALgADCgEJAQAAAA==.',
Fy='Fystie:BAABLgAECn8xAAMYAAcJZRj1AgBXAQAYAAcJZRj1AgBXAQAeAAUJXw6mUQDHAAABLgAECgkJOQAdAEUJAA==.',
Ga='Galacticfox:BAAALgAECgIJAgAAAA==.Galpally:BAABLgAECn8pAAIMAAcJ/hRZgABuAQAMAAcJ/hRZgABuAQAAAA==.Ganzar:BAAALgADCgMJBAABLgAFFAMJFgADAMMkAA==.Garin:BAAALgAECgUJBgAAAA==.',
Ge='Genma:BAAALgAECgQJBAAAAA==.Gennic:BAAALgADCgcJBwAAAA==.Gettinskins:BAAALgAECgMJAwAAAA==.',
Gi='Gishongar:BAAALgAECgkJCgAAAA==.',
Gl='Glorak:BAABLgAECn8nAAIFAAcJdgj4igApAQAFAAcJdgj4igApAQAAAA==.',
Gr='Grashen:BAABLgAECn8oAAIJAAgJ0RlEKQAYAgAJAAgJ0RlEKQAYAgAAAA==.Gravorik:BAABLgAFFH8MAAMLAAMJPAejBABmAAALAAMJXgWjBABmAAAMAAEJbwfQuQBDAAAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDwAAAA==.',
Gs='Gsm:BAABLgAECn9BAAINAAkJRxsIDwB/AgANAAkJRxsIDwB/AgAAAA==.',
Gu='Gulritz:BAAALgAECgIJAgAAAA==.Gulrum:BAAALgADCgEJAQAAAA==.Gurlyman:BAAALgAECgYJDgAAAA==.',
Ha='Haikara:BAAALgADCgMJAwAAAA==.Hante:BAAALgADCgcJEAAAAA==.Hartmonster:BAAALgAECgQJCAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMFAAcJIQVmbQAfAQAFAAYJ0gVmbQAfAQAfAAEJrwF/RgAbAAAAAA==.Hideous:BAAALgAECgQJCgAAAA==.Hikarí:BAAALgADCgYJCQAAAA==.',
Ho='Hobuul:BAAALgADCgcJCwAAAA==.Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgYJEwAAAA==.Hotspur:BAAALgAECgMJAwABLgAECgkJKQAYAEUVAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ia='Iaanditos:BAAALgADCgYJBgAAAA==.',
Ig='Ignath:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilisselia:BAAALgADCgcJBwAAAA==.Ilokana:BAAALgAECgUJEAAAAA==.Ilostmybible:BAAALgAECgMJBQAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAABLgAECn8ZAAIBAAYJXxOPQgA7AQABAAYJXxOPQgA7AQAAAA==.',
It='Itzbarney:BAAALgAECggJEwAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacsknight:BAAALgAECgUJBwAAAA==.Jacspally:BAABLgAECn8qAAMMAAkJdR4AAgBHAgAMAAkJdR4AAgBHAgAgAAEJ0AP3nQAiAAAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8jAAITAAkJkSAjBADZAgATAAkJkSAjBADZAgAAAA==.Jarlath:BAAALgAECgQJBAAAAA==.',
Je='Jebra:BAABLgAECn83AAMeAAkJ8xQ7FwATAgAeAAkJ8xQ7FwATAgATAAEJAAQbjQARAAAAAA==.Jellexy:BAABLgAECn8wAAICAAcJDwYqDQDfAAACAAcJDwYqDQDfAAAAAA==.',
Ji='Jimlahey:BAAALgAECgMJAwABLgAFFAUJGQACADEfAA==.',
Jo='Johnnybone:BAAALgAECgUJBQAAAA==.Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8iAAIKAAUJDRfCCwAYAQAKAAUJDRfCCwAYAQAuAAQKfzIAAgoACQn5HEoRAJYCAAoACQn5HEoRAJYCAAAA.Jonnyfive:BAABLgAECn8WAAIMAAYJBxH4sgAbAQAMAAYJBxH4sgAbAQAAAA==.',
['Jó']='Jósepha:BAAALgADCgQJBAAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIFAAkJ6hfpLwAdAgAFAAkJ6hfpLwAdAgAAAA==.Kaisa:BAAALgAECgEJAgAAAA==.Kalimthor:BAAALgADCgEJAQAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAABLgAECn8fAAIMAAkJ+hN8VgDHAQAMAAkJ+hN8VgDHAQAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8wAAMFAAkJsB2tCAAzAgAFAAkJsB2tCAAzAgAfAAYJEw3CCgBuAQAuAAQKf0EAAx8ACQkiJo8CAIkDAB8ACQkYIo8CAIkDAAUACQkiJiIHACUDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgUJBQAAAA==.Keheo:BAAALgAECgQJCwAAAA==.',
Kh='Khandragho:BAAALgAECgYJBgAAAA==.Khaza:BAAALgAECgUJBQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kiri:BAAALgAECgMJBAABLgAECgkJNQAHAEMRAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn9PAAIEAAkJGSKQAQAdAwAEAAkJGSKQAQAdAwAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIgAAkJbRfBJgD0AQAgAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgUJDgAAAA==.Kruger:BAABLgAECn8jAAIIAAcJ+geMoQD8AAAIAAcJ+geMoQD8AAAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.Krzyhayn:BAAALgADCgUJBQAAAA==.Krzykanaka:BAAALgADCgIJBAAAAA==.',
Kt='Ktanna:BAABLgAECn8XAAIhAAcJaAjPNQDlAAAhAAcJaAjPNQDlAAAAAA==.',
Ku='Kublakhan:BAAALgAECgkJEAAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAYJLwALABMeAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8gAAIJAAkJixwPKgAUAgAJAAkJixwPKgAUAgAAAA==.Lapras:BAEBLgAFFH8OAAMbAAUJeyaQFgC4AQAbAAUJeyaQFgC4AQAZAAEJ6iULCwBxAAAAAA==.Lateralus:BAABLgAECn8wAAIMAAkJvhnFKABfAgAMAAkJvhnFKABfAgAAAA==.Laureli:BAABLgAECn8qAAIBAAcJ0AYHBgDcAAABAAcJ0AYHBgDcAAAAAA==.',
Le='Leeta:BAABLgAECn8pAAITAAkJuBzZCQBLAgATAAkJuBzZCQBLAgAAAA==.Legendx:BAAALgADCgUJBwAAAA==.Letholdus:BAABLgAECn8cAAIEAAkJHhaeAADmAQAEAAkJHhaeAADmAQAAAA==.',
Li='Lightningg:BAABLgAECn8fAAIZAAkJAAyyCQCLAQAZAAkJAAyyCQCLAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgABLgAFFAQJDgACAOwYAA==.',
Lo='Loahavemercy:BAAALgAECgEJAQAAAA==.Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAABLgAECn8UAAILAAYJsgQcNwCDAAALAAYJsgQcNwCDAAAAAA==.Losoz:BAAALgAECgEJAgAAAA==.',
Lu='Lucariel:BAABLgAECn8hAAIDAAkJjRwZGAC2AgADAAkJjRwZGAC2AgAAAA==.Lusilsandrus:BAAALgAECgYJEwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAABLgAFFH8KAAIJAAQJphFcEQDDAAAJAAQJphFcEQDDAAAAAA==.Magusbilly:BAAALgAECgQJBAAAAA==.Mahoutsukai:BAABLgAECn8gAAICAAkJKQP5rQAlAQACAAkJKQP5rQAlAQAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8pAAINAAkJHQjtSQANAQANAAkJHQjtSQANAQAAAA==.',
Me='Mechaknight:BAAALgAECgUJCgAAAA==.',
Mi='Mildrik:BAABLgAECn8fAAIBAAkJCQrZMQCFAQABAAkJCQrZMQCFAQAAAA==.Miracledh:BAABLgAECn8aAAIhAAgJkiVXBgDSAgAhAAgJkiVXBgDSAgAAAA==.Mirkdrak:BAABLgAECn8jAAMbAAcJrAuAUgDlAAAbAAcJrAuAUgDlAAAZAAMJyQJmNgBjAAAAAA==.Mishach:BAAALgAECgQJBAABLgAECggJAgAGAAAAAA==.Misheard:BAACLgAFFH8DAAIXAAIJmBGOmQBCAAAXAAIJmBGOmQBCAAAuAAQKfzoAAhcACQnKIPoUAJsCABcACQnKIPoUAJsCAAAA.Misjudged:BAABLgAECn8YAAQbAAgJexO1LwB5AQAbAAgJexO1LwB5AQAZAAQJhw0dKQDWAAAaAAIJghjmOwA0AAAAAA==.Missus:BAAALgAFFAMJAwAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgQJBQAAAA==.Mizzen:BAABLgAECn8sAAMiAAkJPiGuBgDfAgAiAAkJPiGuBgDfAgAjAAEJawRVpwAdAAABLgAFFAcJGQAQADEUAA==.',
Mo='Mohtavius:BAABLgAECn83AAIVAAkJlhlNCgBMAgAVAAkJlhlNCgBMAgAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn85AAIdAAkJRQmxEQAtAQAdAAkJRQmxEQAtAQAAAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Ms='Msbehavin:BAAALgAECgEJAgAAAA==.',
Mu='Mulnier:BAAALgADCgkJCgAAAA==.Munkìe:BAAALgAECgUJDQABLgAECgkJQQANAEcbAA==.Muura:BAACLgAFFH8GAAIDAAMJiQP3LQCrAAADAAMJiQP3LQCrAAAuAAQKfyEAAgMACQkQDf+nACABAAMACQkQDf+nACABAAAA.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJEgAAAA==.',
Na='Nakavelli:BAAALgAECgEJAQAAAA==.Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8vAAMJAAkJZR2gDgDfAgAJAAkJZR2gDgDfAgAkAAEJRhPACAA+AAAAAA==.Nattal:BAAALgADCgUJBQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJDAAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAgJLQAaAOIdAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Ot='Otwin:BAABLgAECn8aAAMJAAYJ7hWbSwCCAQAJAAYJ7hWbSwCCAQANAAEJnAfQtgAlAAAAAA==.',
Pa='Pahuum:BAAALgAECgYJEwAAAA==.Paimon:BAABLgAECn8cAAILAAgJJxyCCgAhAgALAAgJJxyCCgAhAgABLgAFFAYJGAAbAPkXAA==.Paintrainn:BAABLgAECn8XAAIJAAgJdgGsnQCVAAAJAAgJdgGsnQCVAAAAAA==.Palewhiteman:BAABLgAECn8hAAIgAAgJ5hm3GwAmAgAgAAgJ5hm3GwAmAgAAAA==.Palleigh:BAABLgAECn8uAAIgAAkJoxA0AgCNAQAgAAkJoxA0AgCNAQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Parodoxx:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8pAAIYAAkJRRUCLQD0AQAYAAkJRRUCLQD0AQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8kAAIFAAkJTxmRKAA9AgAFAAkJTxmRKAA9AgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Pl='Plague:BAABLgAFFH8KAAIDAAUJUhs+DwBYAQADAAUJUhs+DwBYAQABLgAFFAMJFgADAMMkAA==.',
Po='Poondor:BAABLgAECn8aAAIgAAkJRRSsGwAmAgAgAAkJRRSsGwAmAgAAAA==.Porsch:BAAALgADCgIJAgAAAA==.',
Pr='Praylorswíft:BAAALgAECgMJAwABLgAECgkJIAACAJ4PAA==.Predaturd:BAAALgAECggJBQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Py='Pyxis:BAAALgADCgEJAQAAAA==.',
Qi='Qindere:BAABLgAECn8cAAICAAgJRghvCQAcAQACAAgJRghvCQAcAQAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn9FAAIFAAkJPhquIwBUAgAFAAkJPhquIwBUAgAAAA==.Rakshaman:BAABLgAECn8cAAIJAAgJ2ApHBwABAQAJAAgJ2ApHBwABAQAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgYJDAABLgAFFAMJFgADAMMkAA==.',
Re='Reihino:BAAALgAECgYJCgAAAA==.Resbak:BAABLgAECn8ZAAIeAAgJ3w7dLQBsAQAeAAgJ3w7dLQBsAQAAAA==.Resiaus:BAABLgAECn89AAIaAAkJyRyZBADgAgAaAAkJyRyZBADgAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECggJEAAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Robinho:BAAALgAECgcJDQAAAA==.Rocketabu:BAAALgAECgQJCwAAAA==.Roctheist:BAABLgAECn8UAAMQAAYJEAbHSAC8AAAQAAYJEAbHSAC8AAAUAAYJEwZgTwCjAAAAAA==.Rocthoeb:BAABLgAECn80AAIVAAkJxRH/EQDoAQAVAAkJxRH/EQDoAQAAAA==.Rodnag:BAAALgADCgEJAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.Rokstedy:BAAALgAECgEJAQAAAA==.',
Ry='Ry:BAABLgAECn8qAAMlAAkJOSPtAQAWAwAlAAkJOSPtAQAWAwAYAAEJ8ASi+gAaAAAAAA==.',
Sa='Saeris:BAAALgAECgUJBwAAAA==.Saintalpha:BAEALgAECgEJAQABLgAECggJFQAHAJkTAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFQAHAJkTAA==.Saintkhal:BAEALgAECgQJDQABLgAECggJFQAHAJkTAA==.Saintmedicus:BAEBLgAECn8VAAMHAAgJmRP/NwAzAQAHAAUJZBf/NwAzAQAQAAMJ0w3jYQCSAAAAAA==.Saintshammy:BAABLgAFFH8FAAIJAAMJWxXpSgDFAAAJAAMJWxXpSgDFAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Saki:BAAALgADCgUJBQAAAA==.Sanctor:BAABLgAECn8dAAIgAAcJeyJ0EgB/AgAgAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Sangairee:BAAALgAECgYJBgAAAA==.Saraya:BAABLgAECn8XAAIgAAkJDRekHgANAgAgAAkJDRekHgANAgAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8jAAIHAAkJYh2RCADsAgAHAAkJYh2RCADsAgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shanoodles:BAAALgAECgUJCQABLgAECgYJBwAGAAAAAA==.Shibaryotaro:BAAALgAECgEJAQAAAA==.Shiftee:BAAALgAECgQJBAABLgAECgcJHAAFABsWAA==.Shinstabber:BAABLgAECn8jAAIWAAkJARTQEwDWAQAWAAkJARTQEwDWAQAAAA==.Shivantice:BAAALgAECgYJBQAAAA==.Shivantis:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Shruggie:BAABLgAECn8+AAMhAAgJ5xkXAQD9AQAhAAgJ5xkXAQD9AQAXAAQJDAPC/QBOAAAAAA==.',
Si='Silven:BAAALgAECgYJDgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8aAAIKAAkJpxn6EgCEAgAKAAkJpxn6EgCEAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8cAAIFAAcJGxZxLwD0AQAFAAcJGxZxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgAECgYJCQAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8tAAMfAAkJuwenEwAmAQAcAAgJKATRLQA3AQAfAAkJnAenEwAmAQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAJADYRAA==.Starlie:BAAALgAECgUJDgAAAA==.Stormstrike:BAAALgAECgcJBgAAAA==.Stratacaster:BAABLgAECn8YAAIIAAcJ0QKG1gCpAAAIAAcJ0QKG1gCpAAAAAA==.Strawberry:BAAALgAFFAEJAQAAAA==.Stuckinwell:BAACLgAFFH8FAAMIAAIJkBjuNQCnAAAIAAIJGBDuNQCnAAAdAAEJlBbVJgBHAAAuAAQKfxsAAwgACQn6GsEzAD0CAAgACAnpFsEzAD0CAB0ABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAIYAAIJhh6QFQC3AAAYAAIJhh6QFQC3AAABLgAFFAgJLQAaAOIdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDwABLgAECgkJVAAWAJUZAA==.Synfyl:BAAALgAECgUJDAAAAA==.Synpathi:BAEALgADCgEJAQABLgAFFAIJCAAmAGQHAA==.Synsyn:BAECLgAFFH8IAAMmAAIJZAf1AwCQAAAmAAIJZAf1AwCQAAAIAAEJVgDB2AAjAAAuAAQKf1QAAyYABwnSE6cNAIIBACYABwnSE6cNAIIBAAgABgnQCXuyAOAAAAAA.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8gAAICAAkJng+giABmAQACAAkJng+giABmAQAAAA==.',
Te='Teanfists:BAAALgAECgYJCgAAAA==.Tearstain:BAAALgADCgcJBwAAAA==.Temna:BAABLgAECn87AAIMAAkJBiT5BQBDAwAMAAkJBiT5BQBDAwAAAA==.Tenari:BAAALgAECggJDwAAAA==.Tevye:BAAALgADCgYJBgAAAA==.',
Th='Theel:BAABLgAECn8qAAIFAAcJxR7gAgAEAgAFAAcJxR7gAgAEAgAAAA==.Thespaniard:BAABLgAECn8fAAIQAAkJqxjzFAAmAgAQAAkJqxjzFAAmAgAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAABLgAECn8WAAITAAgJlQl4MADpAAATAAgJlQl4MADpAAABLgAFFAEJAQAGAAAAAA==.Tinbasher:BAAALgAECgYJDQAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Toast:BAAALgADCgEJAQAAAA==.Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAABLgAECn8eAAMYAAkJ7gnFSQBnAQAYAAkJ7gnFSQBnAQAeAAEJ5QxFjgAyAAAAAA==.Tricky:BAAALgAECgcJEgAAAA==.Triviousox:BAABLgAECn8aAAIMAAcJwhD/jwBSAQAMAAcJwhD/jwBSAQAAAA==.Tryxx:BAAALgADCgUJBQAAAA==.Trêehugger:BAAALgAECgEJAQABLgAECgYJBwAGAAAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJFAABLgAFFAUJEQAnAMYdAA==.Twotvmage:BAABLgAECn8wAAMCAAkJex2qKQB0AgACAAkJex2qKQB0AgAnAAEJIA1+GAAuAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Uneedarez:BAAALgAECgQJBAAAAA==.Unglued:BAAALgAECgYJBgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJDQABLgAECgkJNwAIAA8cAA==.',
Up='Uplift:BAABLgAFFH8FAAIiAAQJXRhDEgAqAQAiAAQJXRhDEgAqAQABLgAFFAgJHgACAJsbAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Ut='Uttrsdeek:BAABLgAFFH8HAAIDAAMJ2hJjIgDcAAADAAMJ2hJjIgDcAAAAAA==.',
Va='Vale:BAAALgAECggJCAAAAA==.Valkky:BAABLgAECn84AAMoAAkJXRbwBwD8AQAoAAkJsxXwBwD8AQAXAAQJOA0VowDOAAAAAA==.Valky:BAAALgAECgEJAQABLgAECgkJOAAoAF0WAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn81AAQHAAkJQxGwHgDZAQAHAAkJ9A2wHgDZAQAUAAcJiw9HNgAnAQAQAAIJ2wRdfQBDAAAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vanity:BAAALgAECgUJBQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECggJEAABLgAECgkJNQAHAEMRAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn85AAIFAAkJbx4IEQDIAgAFAAkJbx4IEQDIAgAAAA==.Versipelliz:BAAALgADCgEJAQAAAA==.Vessna:BAABLgAECn8jAAICAAcJTQd+3gDdAAACAAcJTQd+3gDdAAABLgAECgcJIwAbAKwLAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAABLgAECn8rAAIlAAgJHCNbAABNAgAlAAgJHCNbAABNAgAAAA==.',
Vm='Vmro:BAAALgADCgYJFgAAAA==.',
Vo='Voras:BAAALgAECgYJEQAAAA==.Vorttex:BAAALgAECgUJEQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHQAbAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8pAAIoAAkJkRlHBwAQAgAoAAkJkRlHBwAQAgAAAA==.',
Wh='Whiskeyrick:BAAALgAECgYJCQAAAA==.',
Wi='Wildkanaka:BAAALgAECgEJAQAAAA==.Winters:BAAALgAECgEJAQAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIQAAgJ4RsHEQB4AgAQAAgJ4RsHEQB4AgAAAA==.',
Xi='Xivago:BAAALgAECgUJCQAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAACLgAFFH8HAAIcAAMJcQj1IgDBAAAcAAMJcQj1IgDBAAAuAAQKfxYAAxwACAkDDhElAHUBABwACAkDDhElAHUBAB8ABAmABINqAJQAAAAA.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yo='Yoshino:BAAALgAECgUJBgABLgAECgYJIgACALUKAA==.',
Yu='Yuzuriha:BAAALgAECgYJDwAAAA==.',
Za='Zalamandr:BAAALgAECgEJAgAAAA==.Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgAECgcJDAAAAA==.',
Zo='Zophier:BAAALgAECgQJBgAAAA==.Zouk:BAAALgAECgQJBQAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAABLgAECn8YAAIfAAcJhwzQFQALAQAfAAcJhwzQFQALAQAAAA==.',
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
