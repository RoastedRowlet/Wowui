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

local lookup = {'Unknown-Unknown','Warrior-Fury','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Priest-Discipline','Warrior-Protection','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Rogue-Outlaw','Druid-Guardian','Druid-Balance','Priest-Holy','DeathKnight-Blood','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Warlock-Affliction','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Warlock-Destruction','DemonHunter-Vengeance','Shaman-Enhancement','Druid-Feral','Mage-Arcane',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ab='Abugarcia:BAAALgAECgUJBwAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ad='Adelphie:BAAALgAECgEJAQABLgAECgYJDAABAAAAAA==.',
Ae='Aerro:BAAALgAECgIJAgAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akiryss:BAABLgAECn8bAAICAAkJORL/DwDTAAACAAkJORL/DwDTAAAAAA==.Akusenshi:BAABLgAECn8UAAICAAcJOxBdOgBcAQACAAcJOxBdOgBcAQAAAA==.',
Al='Alarr:BAAALgAECgYJBwABLgAFFAQJDgADAOwYAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alenthia:BAAALgADCgEJAQAAAA==.Alethrix:BAABLgAECn8hAAMEAAgJ0xgQQQD/AQAEAAgJ0xgQQQD/AQAFAAEJxxCIOgAzAAAAAA==.Alexi:BAAALgADCgkJCwAAAA==.Alivis:BAEALgAECgQJCAABLgAFFAMJBQAGAK0VAA==.Alzith:BAAALgAECgQJBQABLgAECgkJIwAEAOQcAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Anderon:BAAALgAECgEJAQAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAkJWwAHAJomAA==.Animocity:BAAALgAECgQJCAAAAA==.',
Ap='Apexalpha:BAAALgAECgQJCAAAAA==.Appletinni:BAABLgAECn8ZAAMIAAcJyAKsDgBmAAAIAAYJQQKsDgBmAAACAAIJdAO5NAAQAAAAAA==.',
Ar='Areto:BAAALgAECgMJAwAAAA==.Arius:BAAALgADCgUJBQAAAA==.Armster:BAAALgAECgcJCgAAAA==.Arold:BAABLgAECn8rAAIJAAkJnRaPNAAHAgAJAAkJnRaPNAAHAgAAAA==.',
As='Asylia:BAACLgAFFH8KAAIKAAQJNhGCCQA5AQAKAAQJNhGCCQA5AQAuAAQKfxcAAgoACAlLGy4hABcCAAoACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8kAAILAAkJCA57QQBoAQALAAkJCA57QQBoAQAAAA==.',
Au='Aulendil:BAAALgAECgEJAQAAAA==.Aurelliae:BAABLgAECn8WAAIGAAgJtBWSVACmAQAGAAgJtBWSVACmAQAAAA==.',
Av='Avesiren:BAABLgAECn8xAAIMAAkJwRXcAgDOAQAMAAkJwRXcAgDOAQAAAA==.',
Ax='Axxion:BAAALgAECgIJAgAAAA==.',
Ay='Ayidá:BAAALgAECggJEwAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAABLgAECn8bAAINAAkJowjUHQDyAAANAAkJowjUHQDyAAAAAA==.Babymamaa:BAABLgAECn8VAAIOAAYJRwWGaQCrAAAOAAYJRwWGaQCrAAAAAA==.Babymuffins:BAABLgAECn8pAAINAAgJqB8ZIwB5AgANAAgJqB8ZIwB5AgAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAABLgAECn8UAAIOAAgJYwlKSAATAQAOAAgJYwlKSAATAQAAAA==.Beklee:BAAALgADCgYJBgAAAA==.Belanda:BAAALgAECgYJDAAAAA==.Belgord:BAAALgAECgYJEwAAAA==.Belin:BAAALgADCgkJFgAAAA==.Bellyn:BAAALgAECggJCgAAAA==.Belmond:BAAALgAECgQJCAAAAA==.Belzac:BAAALgAECgMJAwAAAA==.Bemuse:BAAALgAFFAEJAQAAAA==.',
Bi='Birchwood:BAAALgAECgEJAQAAAA==.',
Bl='Blackmill:BAABLgAECn8UAAIPAAgJZBohBQAuAgAPAAgJZBohBQAuAgAAAA==.Blayrog:BAABLgAECn8qAAIDAAgJuBTabgCcAQADAAgJuBTabgCcAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8vAAMQAAkJGBitDQAOAgAQAAkJzRetDQAOAgACAAYJ/RDSUQBiAQABLgAFFAcJIQARAKMVAA==.Bobamood:BAAALgAFFAIJAwAAAA==.Bobbijoe:BAAALgAECgEJAQAAAA==.Bobbyknocker:BAAALgAECgcJCAAAAA==.Bolf:BAABLgAECn8qAAMSAAkJ4w9YAwC0AQASAAkJDA5YAwC0AQATAAYJ9AueEQDwAAAAAA==.Boneharnen:BAAALgAECgYJDAAAAA==.Boombaaby:BAABLgAECn8xAAIGAAkJsg35XACPAQAGAAkJsg35XACPAQAAAA==.Boomkittie:BAAALgADCgYJBgAAAA==.Bootzee:BAABLgAECn8gAAIKAAcJbxu3KAAbAgAKAAcJbxu3KAAbAgAAAA==.',
Br='Brewglaive:BAAALgAECgEJAwAAAA==.Brewsli:BAAALgAECgMJAwAAAA==.Britishchick:BAAALgAECgYJBgABLgAECgkJKQAUALgcAA==.Brookenoel:BAABLgAECn8oAAIRAAkJ+AgBMABfAQARAAkJ+AgBMABfAQAAAA==.Brunhilian:BAAALgAECgYJDwAAAA==.Bryn:BAAALgADCgIJAgABLgAECgkJNwAVAPMUAA==.',
Bs='Bsê:BAAALgAECgIJBAAAAA==.',
Bu='Buckmaster:BAAALgAECgUJEwAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.Buyeon:BAAALgADCgEJAQAAAA==.',
Ca='Cadun:BAABLgAECn8pAAICAAkJfgf2RwAlAQACAAkJfgf2RwAlAQAAAA==.Calada:BAABLgAECn8qAAIWAAkJLgQODgC9AAAWAAkJLgQODgC9AAAAAA==.Callypso:BAAALgAECgYJBgABLgAECgkJJAALAAgOAA==.Carbion:BAAALgADCgkJCQAAAA==.Carnan:BAAALgADCgEJAQAAAA==.Cassandraa:BAAALgAFFAIJAQAAAA==.',
Ce='Cedarnia:BAAALgADCggJDwAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8eAAIKAAkJOxbGHwBRAgAKAAkJOxbGHwBRAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJDgAAAA==.',
Ck='Ckrazykanaka:BAAALgAECgEJAQAAAA==.',
Co='Corrynn:BAAALgAECgcJEgAAAA==.',
Cr='Craftytotes:BAAALgADCgEJAQAAAA==.Cribbage:BAACLgAFFH8MAAIIAAMJ2B5NFwDhAAAIAAMJ2B5NFwDhAAAuAAQKfykAAwgACQlJImwFAMECAAgACQlJImwFAMECABAAAQnMGrBtAEYAAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgAECgEJAwAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgUJEwAAAA==.',
Cv='Cvaluenigma:BAAALgAECgEJAQAAAA==.',
Cy='Cynosure:BAABLgAECn8yAAISAAkJvRkdEQAgAgASAAkJvRkdEQAgAgAAAA==.Cytronsneak:BAABLgAECn8VAAISAAYJog/1LwAgAQASAAYJog/1LwAgAQAAAA==.',
Da='Dabb:BAAALgAECgIJAgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgUJDQAAAA==.Daela:BAAALgADCgYJBgAAAA==.Daliå:BAAALgAECgEJAQAAAA==.Dalrook:BAAALgAECgEJAQAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8kAAIJAAkJdgyvVwCWAQAJAAkJdgyvVwCWAQAAAA==.Darkduchess:BAAALgAECgQJAwAAAA==.Darkheaven:BAABLgAECn8eAAINAAkJagoIdQCEAQANAAkJagoIdQCEAQAAAA==.Darkkanaka:BAAALgADCgEJAwAAAA==.Darknyss:BAAALgADCgMJAwAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgMJAwAAAA==.Dazarek:BAABLgAECn8qAAIXAAkJQAagKwD9AAAXAAkJQAagKwD9AAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Deathbot:BAAALgAECgUJBQAAAA==.Deathrazor:BAAALgAFFAEJAQAAAA==.Demium:BAACLgAFFH8aAAIYAAcJOBhrKwB6AQAYAAcJOBhrKwB6AQAuAAQKfyoAAhgACQk5IsMeAFwCABgACQk5IsMeAFwCAAEuAAQKBQkKAAEAAAAA.Demonkanaka:BAAALgADCgMJBgAAAA==.Denae:BAAALgAECgEJAwABLgAECgYJDAABAAAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgAECgYJBgAAAA==.Devinetoro:BAABLgAECn8vAAINAAkJVQhUhgBjAQANAAkJVQhUhgBjAQAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAIZAAkJGRcmLAD/AQAZAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn84AAQaAAkJeBoyAwBsAgAaAAkJeBoyAwBsAgAbAAQJTRIzLQCBAAAcAAMJLQYieQBxAAAAAA==.',
Dk='Dklunar:BAABLgAFFH8HAAIEAAQJhQMRywCYAAAEAAQJhQMRywCYAAABLgAFFAcJFQAZAJAUAA==.',
Do='Dopo:BAAALgAECgcJAgAAAA==.Doree:BAAALgAECgUJBQAAAA==.Dotdotoops:BAAALgAECgEJAQAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAYJIQAdAI4TAA==.Dreadsofdeth:BAABLgAECn8VAAIDAAYJixh1ngCZAQADAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJEAAAAA==.Drklhtkanaka:BAAALgAECgEJAgAAAA==.Drunkenbilly:BAAALgAECgIJAgAAAA==.Drustone:BAAALgADCgEJAQAAAA==.',
Dw='Dwangler:BAAALgAECgEJAQAAAA==.Dwydeshruke:BAAALgADCgMJAwAAAA==.',
['Dê']='Dêv:BAABLgAECn8yAAIJAAgJBBI4VgCaAQAJAAgJBBI4VgCaAQAAAA==.',
Ea='Earthroot:BAAALgADCgEJAQAAAA==.',
Eh='Ehtar:BAAALgAECgYJBgABLgAFFAcJIQARAKMVAA==.',
Ei='Einheri:BAABLgAECn9IAAICAAkJ3B4oAgB9AgACAAkJ3B4oAgB9AgAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgAECgYJCAAAAA==.Elexie:BAAALgAECgQJBAABLgAECgYJDAABAAAAAA==.Elracc:BAAALgAECggJDwAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8VAAISAAMJyiBkIgASAQASAAMJyiBkIgASAQAuAAQKfywAAhIACQkvGmwPADYCABIACQkvGmwPADYCAAAA.Enoira:BAAALgAECgEJAgAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAABLgAECn8uAAIMAAkJ1hbUAgDPAQAMAAkJ1hbUAgDPAQAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Et='Ethel:BAAALgAECgIJAgAAAA==.',
Ev='Evillizard:BAABLgAECn8XAAIcAAgJ2wpiQAAoAQAcAAgJ2wpiQAAoAQAAAA==.',
Ex='Exhumer:BAABLgAECn8oAAINAAkJoSV7DgDyAgANAAkJoSV7DgDyAgAAAA==.',
Fa='Faffard:BAABLgAECn8lAAIGAAkJlw+iJwC8AAAGAAkJlw+iJwC8AAABLgAECgkJOgAZAK0VAA==.Fame:BAAALgAFFAMJAwABLgAFFAkJIwAcAD4aAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgUJBwAAAA==.',
Fe='Fearbilly:BAAALgAECgUJCQAAAA==.Felbilly:BAAALgAECgIJAgAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAABLgAECn8tAAMZAAkJfwRRDwC4AAAZAAkJfwRRDwC4AAAVAAEJrAHvqgASAAAAAA==.',
Fi='Filetminyon:BAAALgADCgMJAwAAAA==.Fily:BAAALgAECgYJBgABLgAECggJEwABAAAAAA==.',
Fl='Flap:BAACLgAFFH8jAAIcAAkJPhpwBgBBAgAcAAkJPhpwBgBBAgAuAAQKfykAAxwACQlVHq0DAJABABwACQlVHq0DAJABABoAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fu='Funenix:BAAALgADCggJDQAAAA==.Furbalkanaka:BAAALgADCgEJAQAAAA==.',
Fy='Fystie:BAABLgAECn86AAMZAAkJrRWKBQCvAQAZAAkJrRWKBQCvAQAVAAcJSRCmUQDHAAAAAA==.',
Ga='Galacticfox:BAAALgAECgIJAgAAAA==.Galpally:BAABLgAECn85AAINAAgJ7BYFCgDPAQANAAgJ7BYFCgDPAQAAAA==.Ganzar:BAAALgADCgMJBAAAAA==.Garin:BAAALgAECgUJBgAAAA==.Gazgulthraka:BAAALgAECgIJAgAAAA==.',
Ge='Genma:BAAALgAECgQJBAAAAA==.Gennic:BAAALgADCgcJBwAAAA==.Gettinskins:BAAALgAECgMJAwAAAA==.',
Gh='Ghenghiskhan:BAAALgAECgMJAQAAAA==.',
Gi='Gishongar:BAAALgAFFAIJAgAAAA==.',
Gl='Glorak:BAABLgAECn8nAAIGAAcJdgj4igApAQAGAAcJdgj4igApAQAAAA==.',
Gr='Grashen:BAABLgAECn8xAAIKAAkJKxwaAwCUAgAKAAkJKxwaAwCUAgAAAA==.Gravorik:BAABLgAFFH8UAAMMAAMJPAfuDABXAAAMAAMJ4wbuDABXAAANAAEJbwfQuQBDAAAAAA==.Greefkarga:BAAALgAECgIJAgAAAA==.Grogu:BAAALgAECgYJDwAAAA==.',
Gs='Gsm:BAABLgAECn9GAAIOAAkJShsIDwB/AgAOAAkJShsIDwB/AgAAAA==.',
Gu='Gulritz:BAAALgAECgIJAgAAAA==.Gulrum:BAAALgADCgEJAQAAAA==.Gurlyman:BAAALgAECgcJDwAAAA==.',
Ha='Haikara:BAAALgADCgMJAwAAAA==.Hante:BAAALgADCgcJEAAAAA==.Hartmonster:BAAALgAECgQJCAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Healzers:BAEALgADCgEJAQABLgAFFAIJDAAeAI0IAA==.Hellmouth:BAAALgADCgQJBAAAAA==.Hemazo:BAAALgADCgIJAgAAAA==.',
Hi='Hiawassee:BAABLgAECn8VAAMGAAgJcQVmbQAfAQAGAAcJEQZmbQAfAQAfAAEJrwF/RgAbAAAAAA==.Hideous:BAAALgAECgQJCwAAAA==.Hikarí:BAAALgAECgYJDwAAAA==.',
Ho='Hobuul:BAABLgAFFH8IAAIKAAMJEhK2KQCkAAAKAAMJEhK2KQCkAAAAAA==.Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoofnstien:BAAALgAFFAMJAwAAAA==.Hoompukka:BAABLgAECn8UAAIHAAYJog8zNgA7AQAHAAYJog8zNgA7AQAAAA==.Hotspur:BAAALgAECgMJAwABLgAECgkJKQAZAEUVAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ia='Iaanditos:BAAALgADCgYJBgAAAA==.',
Ig='Ignath:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilisselia:BAAALgADCgcJBwAAAA==.Ilokana:BAABLgAECn8YAAIdAAgJFQQcCAC/AAAdAAgJFQQcCAC/AAAAAA==.Ilostmybible:BAAALgAECgMJCAAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAABLgAECn8ZAAICAAYJXxOPQgA7AQACAAYJXxOPQgA7AQAAAA==.',
It='Itzbarney:BAAALgAECggJEwAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacsdruid:BAAALgADCgMJAwAAAA==.Jacsknight:BAAALgAECgUJBwAAAA==.Jacspally:BAABLgAECn8rAAMNAAkJTh6fBgAvAgANAAkJTh6fBgAvAgAgAAEJ0AP3nQAiAAAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8jAAIUAAkJkSAjBADZAgAUAAkJkSAjBADZAgAAAA==.Jarlath:BAAALgAECgQJBAAAAA==.',
Je='Jebra:BAABLgAECn83AAMVAAkJ8xQ7FwATAgAVAAkJ8xQ7FwATAgAUAAEJAAQbjQARAAAAAA==.Jellexy:BAABLgAECn83AAIDAAkJcQaQGAAWAQADAAkJcQaQGAAWAQAAAA==.',
Ji='Jimlahey:BAAALgAECgMJAwABLgAFFAUJGgADAF0fAA==.',
Jo='Johnnybone:BAAALgAECgUJBQAAAA==.Jolah:BAAALgAECgYJBgAAAA==.Jolahbae:BAACLgAFFH8iAAILAAUJDRd3IABrAQALAAUJDRd3IABrAQAuAAQKfzIAAgsACQn5HEoRAJYCAAsACQn5HEoRAJYCAAAA.Jonnyfive:BAABLgAECn8XAAINAAYJphH4sgAbAQANAAYJphH4sgAbAQAAAA==.',
['Jó']='Jósepha:BAAALgADCgQJBAAAAA==.',
Ka='Kaehlen:BAAALgAFFAEJAQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIGAAkJ6hfpLwAdAgAGAAkJ6hfpLwAdAgAAAA==.Kaisa:BAAALgAECgEJAgAAAA==.Kalimthor:BAAALgADCgEJAQAAAA==.Kanakafist:BAAALgAECgEJAQAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAABLgAECn8fAAINAAkJ+RN8VgDHAQANAAkJ+RN8VgDHAQAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH86AAMGAAkJ4SBjAQAVAwAGAAkJ4SBjAQAVAwAfAAYJEw3CCgBuAQAuAAQKf0EAAx8ACQkiJo8CAIkDAB8ACQkYIo8CAIkDAAYACQkiJiIHACUDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgUJBQAAAA==.Keheo:BAAALgAECgQJCwAAAA==.',
Kh='Khandragho:BAAALgAECgYJBgAAAA==.Khaza:BAAALgAECgUJBQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kiri:BAAALgAECgQJBQABLgAECgkJNgAHAFkRAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAACLgAFFH8FAAIFAAMJagzGDgC7AAAFAAMJagzGDgC7AAAuAAQKf08AAgUACQkZIpABAB0DAAUACQkZIpABAB0DAAAA.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIgAAkJbRfBJgD0AQAgAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgYJDwAAAA==.Kruger:BAABLgAECn8jAAIJAAcJ+geMoQD8AAAJAAcJ+geMoQD8AAAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.Krzyhayn:BAAALgAECgEJAQAAAA==.Krzykanaka:BAAALgADCgIJBAAAAA==.',
Kt='Ktanna:BAABLgAECn8XAAIhAAcJaAjPNQDlAAAhAAcJaAjPNQDlAAAAAA==.',
Ku='Kublakhan:BAAALgAECgkJEAAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAgJMwAMAAIZAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
['Kõ']='Kõrin:BAAALgAECgYJBgAAAA==.',
La='Lakhi:BAABLgAECn8gAAIKAAkJixwPKgAUAgAKAAkJixwPKgAUAgAAAA==.Lapras:BAEBLgAFFH8OAAMcAAUJeyaQFgC4AQAcAAUJeyaQFgC4AQAaAAEJ6iULCwBxAAAAAA==.Lateralus:BAABLgAECn8wAAINAAkJvhnFKABfAgANAAkJvhnFKABfAgAAAA==.Laureli:BAABLgAECn8zAAICAAkJKwg1CwAYAQACAAkJKwg1CwAYAQAAAA==.',
Le='Leeta:BAABLgAECn8pAAIUAAkJuBzZCQBLAgAUAAkJuBzZCQBLAgAAAA==.Legendx:BAAALgADCgUJBwAAAA==.Leorra:BAAALgAECgEJAQAAAA==.Letholdus:BAABLgAECn8dAAIFAAkJ8BUQAgDqAQAFAAkJ8BUQAgDqAQAAAA==.',
Li='Lightningg:BAABLgAECn8fAAIaAAkJAAyyCQCLAQAaAAkJAAyyCQCLAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgABLgAFFAQJDgADAOwYAA==.',
Lo='Loahavemercy:BAAALgAECgEJAQAAAA==.Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAABLgAECn8UAAIMAAYJsgQcNwCDAAAMAAYJsgQcNwCDAAAAAA==.Losoz:BAAALgAECgEJAgAAAA==.',
Lu='Lucariel:BAABLgAECn8jAAIEAAkJ5BwZGAC2AgAEAAkJ5BwZGAC2AgAAAA==.Lusilsandrus:BAAALgAECgYJEwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAABLgAFFH8QAAIKAAQJphGQIADRAAAKAAQJphGQIADRAAAAAA==.Magusbilly:BAAALgAECgQJBQAAAA==.Mahoutsukai:BAABLgAECn8gAAIDAAkJKQP5rQAlAQADAAkJKQP5rQAlAQAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8pAAIOAAkJHAjtSQANAQAOAAkJHAjtSQANAQAAAA==.',
Me='Mechaknight:BAAALgAECgUJCgAAAA==.Mellaise:BAAALgADCgMJCAAAAA==.',
Mi='Mildrik:BAABLgAECn8fAAICAAkJCQrZMQCFAQACAAkJCQrZMQCFAQAAAA==.Miracledh:BAABLgAECn8aAAIhAAgJkiVXBgDSAgAhAAgJkiVXBgDSAgAAAA==.Mirkdrak:BAABLgAECn8qAAMcAAkJ5QsCBwAVAQAcAAkJ5QsCBwAVAQAaAAMJyQJmNgBjAAAAAA==.Mishach:BAAALgAECgQJBQABLgAECggJAgABAAAAAA==.Misheard:BAACLgAFFH8DAAIYAAIJmBGOmQBCAAAYAAIJmBGOmQBCAAAuAAQKfzoAAhgACQnKIPoUAJsCABgACQnKIPoUAJsCAAAA.Misjudged:BAABLgAECn8YAAQcAAgJexO1LwB5AQAcAAgJexO1LwB5AQAaAAQJhw0dKQDWAAAbAAIJghjmOwA0AAAAAA==.Missus:BAAALgAFFAMJAwAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgQJBQAAAA==.Mizzen:BAABLgAECn8sAAMiAAkJPSGuBgDfAgAiAAkJPSGuBgDfAgAjAAEJawRVpwAdAAABLgAFFAcJIQARAKMVAA==.',
Mo='Mohtavius:BAABLgAECn83AAIIAAkJlhlNCgBMAgAIAAkJlhlNCgBMAgAAAA==.Mohz:BAAALgADCggJDQAAAA==.Mommydearest:BAABLgAECn85AAIkAAkJRQmxEQAtAQAkAAkJRQmxEQAtAQABLgAECgkJOgAZAK0VAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Moontotem:BAAALgADCgEJAQAAAA==.Mori:BAAALgADCgIJAgABLgAECgkJOAAlAF0WAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Ms='Msbehavin:BAAALgAECgIJBAAAAA==.',
Mu='Mulnier:BAAALgADCgkJCgAAAA==.Munkìe:BAAALgAECgUJDQABLgAECgkJRgAOAEobAA==.Muura:BAACLgAFFH8MAAIEAAMJxAUtWwClAAAEAAMJxAUtWwClAAAuAAQKfyEAAgQACQkQDf+nACABAAQACQkQDf+nACABAAAA.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJEgAAAA==.',
Na='Nabsta:BAAALgAECgEJAgAAAA==.Nakavelli:BAAALgAECgEJAQAAAA==.Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn83AAMKAAkJRx82AgDbAgAKAAkJRx82AgDbAgAmAAEJRhN2FgA6AAAAAA==.Nattal:BAAALgADCgUJBQAAAA==.Nausica:BAAALgAFFAIJAQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJDAAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAkJPgAbAHEdAA==.Nekorii:BAAALgAECgUJCQAAAA==.Nexis:BAAALgAECgUJBQAAAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAABAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.Nowyhn:BAAALgAFFAIJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Or='Oraein:BAAALgAECgYJCAAAAA==.Orgasmicfox:BAAALgAECgQJBAAAAA==.',
Ot='Otwin:BAABLgAECn8bAAMKAAYJ7hWbSwCCAQAKAAYJ7hWbSwCCAQAOAAEJDhBGLQAvAAAAAA==.',
Pa='Pahuum:BAAALgAECgcJEwAAAA==.Paimon:BAABLgAECn8nAAIMAAgJLh2CCgAhAgAMAAgJLh2CCgAhAgABLgAFFAkJIwAcAD4aAA==.Paintrainn:BAABLgAECn8XAAIKAAgJdgGsnQCVAAAKAAgJdgGsnQCVAAAAAA==.Palewhiteman:BAABLgAECn8hAAIgAAgJ5hm3GwAmAgAgAAgJ5hm3GwAmAgAAAA==.Palleigh:BAABLgAECn8vAAIgAAkJEhFBBwBqAQAgAAkJEhFBBwBqAQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Parodoxx:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8pAAIZAAkJRRUCLQD0AQAZAAkJRRUCLQD0AQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8kAAIGAAkJTxmRKAA9AgAGAAkJTxmRKAA9AgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.Piratepatch:BAAALgADCgEJAQAAAA==.',
Pl='Plague:BAABLgAFFH8LAAIEAAYJjBiOHwBpAQAEAAYJjBiOHwBpAQAAAA==.',
Po='Poondor:BAABLgAECn8aAAIgAAkJRRSsGwAmAgAgAAkJRRSsGwAmAgAAAA==.Porsch:BAAALgADCgIJAgAAAA==.Poutine:BAAALgADCgEJAQAAAA==.',
Pr='Praylorswíft:BAAALgAECgMJAwABLgAECgkJIAADAJ4PAA==.Predaturd:BAAALgAFFAEJAQAAAA==.Prettydruid:BAAALgAECgEJAQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Py='Pyxis:BAAALgADCgEJAQAAAA==.',
Qi='Qindere:BAABLgAECn8lAAIDAAkJEAzcDwBrAQADAAkJEAzcDwBrAQAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn9GAAIGAAkJPhquIwBUAgAGAAkJPhquIwBUAgAAAA==.Rakshaman:BAABLgAECn8qAAIKAAkJxw8XCgCaAQAKAAkJxw8XCgCaAQAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgYJDAAAAA==.Rawrdadd:BAAALgADCgMJAwAAAA==.',
Re='Reihino:BAABLgAECn8XAAIDAAcJxwXFKAC0AAADAAcJxwXFKAC0AAAAAA==.Resbak:BAABLgAECn8ZAAIVAAgJ3w7dLQBsAQAVAAgJ3w7dLQBsAQAAAA==.Resiaus:BAABLgAECn89AAIbAAkJyRyZBADgAgAbAAkJyRyZBADgAgAAAA==.Rexios:BAAALgAECgEJAQAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECggJEAAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Robinho:BAAALgAECgcJDQAAAA==.Rocketabu:BAAALgAECgQJCwAAAA==.Roctheist:BAABLgAECn8UAAMRAAYJEAbHSAC8AAARAAYJEAbHSAC8AAAWAAYJEwZgTwCjAAAAAA==.Rocthoeb:BAABLgAECn80AAIIAAkJxRH/EQDoAQAIAAkJxRH/EQDoAQAAAA==.Rodnag:BAAALgADCgEJAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.Rokstedy:BAAALgAECgYJBgAAAA==.',
Ry='Ry:BAABLgAECn8qAAMnAAkJOSPtAQAWAwAnAAkJOSPtAQAWAwAZAAEJ8ASi+gAaAAAAAA==.',
Sa='Saeris:BAAALgAECgUJBwAAAA==.Saintalpha:BAEALgAECgEJAQABLgAECggJFwAHAOwTAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFwAHAOwTAA==.Saintkhal:BAEALgAECgQJDQABLgAECggJFwAHAOwTAA==.Saintmedicus:BAEBLgAECn8XAAMHAAgJ7BP/NwAzAQAHAAUJZBf/NwAzAQARAAMJXw7jYQCSAAAAAA==.Saintshammy:BAABLgAFFH8FAAIKAAMJWxXpSgDFAAAKAAMJWxXpSgDFAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Sanctor:BAABLgAECn8dAAIgAAcJeyJ0EgB/AgAgAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Sangairee:BAAALgAECgYJBgAAAA==.Saraya:BAABLgAECn8XAAIgAAkJFhekHgANAgAgAAkJFhekHgANAgAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8jAAIHAAkJYh2RCADsAgAHAAkJYh2RCADsAgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shanoodles:BAAALgAECgUJCQABLgAECggJEwABAAAAAA==.Shibaryotaro:BAAALgAECgEJAQAAAA==.Shiftee:BAAALgAECgQJBAABLgAECgcJHAAGABsWAA==.Shinstabber:BAABLgAECn8jAAIXAAkJARTQEwDWAQAXAAkJARTQEwDWAQAAAA==.Shivantice:BAABLgAECn8dAAIDAAgJuRbJCADrAQADAAgJuRbJCADrAQAAAA==.Shivantis:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwABAAAAAA==.Shruggie:BAABLgAECn9jAAMhAAkJUxs3AgBxAgAhAAkJUxs3AgBxAgAYAAQJcw0kHACrAAAAAA==.',
Si='Silven:BAAALgAECgYJDgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8aAAILAAkJpxn6EgCEAgALAAkJpxn6EgCEAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8cAAIGAAcJGxZxLwD0AQAGAAcJGxZxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgAECgYJCgAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8tAAMfAAkJuwenEwAmAQAdAAgJKATRLQA3AQAfAAkJnAenEwAmAQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAKADYRAA==.Starlie:BAAALgAECgUJDgAAAA==.Stormstrike:BAAALgAECgcJBgAAAA==.Stratacaster:BAABLgAECn8YAAIJAAcJ0QKG1gCpAAAJAAcJ0QKG1gCpAAAAAA==.Strawberry:BAAALgAFFAEJAQAAAA==.Stuckinwell:BAACLgAFFH8FAAMJAAIJkBjuNQCnAAAJAAIJGBDuNQCnAAAkAAEJlBbVJgBHAAAuAAQKfxsAAwkACQn6GsEzAD0CAAkACAnpFsEzAD0CACQABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAIZAAIJhh6QFQC3AAAZAAIJhh6QFQC3AAABLgAFFAkJPgAbAHEdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAFFAEJAQABLgAECgkJcAAXAP4dAA==.Synfyl:BAEBLgAECn8bAAIEAAYJhRTQEAA0AQAEAAYJhRTQEAA0AQABLgAFFAIJDAAeAI0IAA==.Synsyn:BAECLgAFFH8MAAMeAAIJjQgHCgCFAAAeAAIJjQgHCgCFAAAJAAEJmgQucQAuAAAuAAQKf2IAAx4ACAm+FqECAIYBAB4ACAk6FqECAIYBAAkABgnaEK8WAMAAAAAA.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgMJAgAAAA==.Taílorswift:BAABLgAECn8gAAIDAAkJng+giABmAQADAAkJng+giABmAQAAAA==.',
Te='Teanfists:BAAALgAECgYJCgAAAA==.Tearstain:BAAALgADCgcJBwAAAA==.Tehsticlees:BAAALgADCgMJAwAAAA==.Telise:BAAALgADCgEJAQAAAA==.Temna:BAABLgAECn87AAINAAkJBiT5BQBDAwANAAkJBiT5BQBDAwAAAA==.Tenari:BAAALgAECggJDwAAAA==.Terra:BAAALgAECgEJAQAAAA==.Tevye:BAAALgADCgYJBgAAAA==.',
Th='Theel:BAABLgAECn8uAAIGAAgJNR29BgAwAgAGAAgJNR29BgAwAgAAAA==.Theruss:BAAALgAECgEJAQAAAA==.Thespaniard:BAABLgAECn8fAAIRAAkJqxjzFAAmAgARAAkJqxjzFAAmAgAAAA==.Thetingler:BAAALgADCgMJAwAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAABLgAECn8WAAIUAAgJlQl4MADpAAAUAAgJlQl4MADpAAABLgAFFAEJAQABAAAAAA==.Tinbasher:BAAALgAECgcJEAAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Toast:BAAALgADCgEJAQAAAA==.Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAABLgAECn8eAAMZAAkJ7gnFSQBnAQAZAAkJ7gnFSQBnAQAVAAEJ5QxFjgAyAAAAAA==.Tricky:BAABLgAECn8ZAAIDAAgJGhQ4DgCBAQADAAgJGhQ4DgCBAQAAAA==.Triviousox:BAABLgAECn8aAAINAAcJwhD/jwBSAQANAAcJwhD/jwBSAQAAAA==.Tryxx:BAAALgADCgUJBQAAAA==.Trêehugger:BAAALgAECgEJAQABLgAECggJEwABAAAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJFAABLgAFFAcJEwAoAAsaAA==.Twotvmage:BAABLgAECn8wAAMDAAkJex2qKQB0AgADAAkJex2qKQB0AgAoAAEJIA1+GAAuAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Uneedarez:BAAALgAECgQJBAAAAA==.Unglued:BAAALgAECgYJBgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJDQABLgAECgkJNwAJAA8cAA==.Unplugged:BAAALgADCgIJAgAAAA==.',
Up='Uplift:BAABLgAFFH8FAAIiAAQJXRhDEgAqAQAiAAQJXRhDEgAqAQABLgAFFAgJHgADAJsbAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Ut='Uttrsdeek:BAABLgAFFH8IAAIEAAMJ2hLJTADBAAAEAAMJ2hLJTADBAAAAAA==.',
Va='Vale:BAAALgAECggJCQAAAA==.Valkky:BAABLgAECn84AAMlAAkJXRbwBwD8AQAlAAkJsxXwBwD8AQAYAAQJOA0VowDOAAAAAA==.Valky:BAAALgAECgEJAQABLgAECgkJOAAlAF0WAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn82AAQHAAkJWRGwHgDZAQAHAAkJCg6wHgDZAQAWAAcJiw9HNgAnAQARAAIJ2wRdfQBDAAAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vandeta:BAAALgAECgEJAQAAAA==.Vanity:BAAALgAECgUJBQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECggJEAABLgAECgkJNgAHAFkRAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn85AAIGAAkJbx4IEQDIAgAGAAkJbx4IEQDIAgAAAA==.Versipelliz:BAAALgADCgEJAQAAAA==.Vessna:BAABLgAECn8qAAIDAAkJSQlhFgAoAQADAAkJSQlhFgAoAQABLgAECgkJKgAcAOULAA==.Veti:BAAALgAECgUJBQAAAA==.Vextrøs:BAAALgAECgIJAgAAAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAABLgAECn80AAInAAkJ9CKcAADjAgAnAAkJ9CKcAADjAgAAAA==.',
Vm='Vmro:BAAALgADCgYJFgAAAA==.',
Vo='Voras:BAABLgAECn8bAAMKAAkJpxbWBwDRAQAKAAkJpxbWBwDRAQAOAAEJJAthsQAoAAAAAA==.Vorttex:BAAALgAECgYJEgAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAkJRAAcAMEfAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8pAAIlAAkJixlHBwAQAgAlAAkJixlHBwAQAgAAAA==.',
Wh='Whiskeyrick:BAAALgAECgcJEwAAAA==.',
Wi='Wildkanaka:BAAALgAECgEJAQAAAA==.Winters:BAAALgAECgEJAQAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIRAAgJ4RsHEQB4AgARAAgJ4RsHEQB4AgAAAA==.',
Xi='Xivago:BAAALgAECgUJCgAAAA==.',
Xl='Xlotec:BAAALgADCgYJCAAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAACLgAFFH8HAAIdAAMJcQj1IgDBAAAdAAMJcQj1IgDBAAAuAAQKfxYAAx0ACAkDDhElAHUBAB0ACAkDDhElAHUBAB8ABAmABINqAJQAAAAA.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yo='Yoshino:BAAALgAECgUJBgABLgAECgkJKwADAJsMAA==.',
Yu='Yuzuriha:BAAALgAECgYJDwAAAA==.',
Za='Zalamandr:BAAALgAECgEJAwAAAA==.Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgAFFAEJBAAAAA==.',
Zo='Zophier:BAAALgAECgQJBwAAAA==.Zouk:BAABLgAECn8VAAIKAAcJyw30DgA+AQAKAAcJyw30DgA+AQAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âs']='Âsura:BAAALgAECgYJBgAAAA==.',
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
