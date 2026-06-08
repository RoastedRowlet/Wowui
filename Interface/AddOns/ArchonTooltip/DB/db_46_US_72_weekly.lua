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

local lookup = {'Warrior-Fury','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Rogue-Outlaw','Warrior-Protection','Rogue-Subtlety','DeathKnight-Blood','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Destruction','Druid-Balance','Shaman-Elemental','Paladin-Holy','Druid-Guardian','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Priest-Holy','Druid-Feral','Hunter-Survival','Warlock-Affliction','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ab='Abugarcia:BAAALgAECgEJAgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAABLgAECn8WAAIBAAcJYxB8RQAlAQABAAcJYxB8RQAlAQAAAA==.Akusenshi:BAABLgAECn8UAAIBAAcJOxAeNwBjAQABAAcJOxAeNwBjAQAAAA==.',
Al='Alarr:BAAALgAECgYJBwABLgAFFAQJDAACAOwYAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAABLgAECn8gAAMDAAgJUhYSSgDcAQADAAgJUhYSSgDcAQAEAAEJxxDDNAA2AAAAAA==.Alexi:BAAALgADCgkJCwAAAA==.Alivis:BAEALgAECgQJBAABLgAECgkJMAAFAGkgAA==.Alzith:BAAALgAECgQJBQABLgAECgkJGAADAG8YAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAkJOgAHAFclAA==.Animocity:BAAALgADCgUJBQAAAA==.',
Ap='Apexalpha:BAAALgAECgQJCAAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgAECgcJCgAAAA==.Arold:BAABLgAECn8lAAIIAAkJRhbvLwATAgAIAAkJRhbvLwATAgAAAA==.',
As='Asylia:BAACLgAFFH8KAAIJAAQJNhGCCQA5AQAJAAQJNhGCCQA5AQAuAAQKfxcAAgkACAlLGy4hABcCAAkACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8iAAIKAAgJqg6/PABjAQAKAAgJqg6/PABjAQAAAA==.',
Au='Aurelliae:BAABLgAECn8WAAIFAAgJtBXKTQCsAQAFAAgJtBXKTQCsAQAAAA==.',
Av='Avesiren:BAABLgAECn8lAAILAAcJLhI+GQBEAQALAAcJLhI+GQBEAQAAAA==.',
Ax='Axxion:BAAALgADCgYJBgAAAA==.',
Ay='Ayidá:BAAALgAECgcJEgAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECggJDwAAAA==.Babymamaa:BAAALgAECgUJDgAAAA==.Babymuffins:BAABLgAECn8nAAIMAAgJaB8wIQB4AgAMAAgJaB8wIQB4AgAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAAALgAECggJEwAAAA==.Beklee:BAAALgADCgUJBQAAAA==.Belanda:BAAALgAECgMJBQAAAA==.Belgord:BAAALgAECgYJEwAAAA==.Belin:BAAALgADCgkJFgAAAA==.Belmond:BAAALgAECgQJCAAAAA==.',
Bl='Blackmill:BAABLgAECn8UAAINAAgJZBrXBAAwAgANAAgJZBrXBAAwAgAAAA==.Blayrog:BAABLgAECn8pAAICAAgJuBQAagChAQACAAgJuBQAagChAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8vAAMOAAkJGBjcDAAPAgAOAAkJzRfcDAAPAgABAAYJ/RDSUQBiAQABLgAFFAYJFwAPALEUAA==.Bobamood:BAAALgAECgIJAgAAAA==.Bobbyknocker:BAAALgAECgcJCAAAAA==.Bolf:BAABLgAECn8ZAAIQAAYJ9AvREADxAAAQAAYJ9AvREADxAAAAAA==.Boombaaby:BAABLgAECn8jAAIFAAgJlwynXACDAQAFAAgJlwynXACDAQAAAA==.Bootzee:BAABLgAECn8gAAIJAAcJbxv+JQAdAgAJAAcJbxv+JQAdAgAAAA==.',
Br='Brewglaive:BAAALgAECgEJAgAAAA==.Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAABLgAECn8iAAIPAAgJLAkONABAAQAPAAgJLAkONABAAQAAAA==.Brunhilian:BAAALgAECgUJCQAAAA==.',
Bu='Buckmaster:BAAALgAECgMJBAAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAABLgAECn8nAAIBAAgJWQdlQwAuAQABAAgJWQdlQwAuAQAAAA==.Calada:BAAALgAECgYJEgAAAA==.Callypso:BAAALgAECgYJBgABLgAECggJIgAKAKoOAA==.Carbion:BAAALgADCgkJCQAAAA==.',
Ce='Cedarnia:BAAALgADCggJBwAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAgAGAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8eAAIJAAkJOxbiHQBRAgAJAAkJOxbiHQBRAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJDgAAAA==.',
Co='Corrynn:BAAALgAECgcJEgAAAA==.',
Cr='Cribbage:BAACLgAFFH8JAAIRAAMJwB6FFADsAAARAAMJwB6FFADsAAAuAAQKfykAAxEACQlJIs8EAMkCABEACQlJIs8EAMkCAA4AAQnMGtxlAEYAAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgADCggJDwAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgUJEwAAAA==.',
Cy='Cynosure:BAABLgAECn8xAAISAAkJvRnZDwAjAgASAAkJvRnZDwAjAgAAAA==.Cytronsneak:BAAALgAECgUJDQAAAA==.',
Da='Dabb:BAAALgADCggJDgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgUJDQAAAA==.Daela:BAAALgADCgYJBgAAAA==.Daliå:BAAALgAECgEJAQAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8hAAIIAAkJygumUwCcAQAIAAkJygumUwCcAQAAAA==.Darkheaven:BAABLgAECn8cAAIMAAkJmgimeABxAQAMAAkJmgimeABxAQAAAA==.Darkkanaka:BAAALgADCgEJAgAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAABLgAECn8dAAITAAgJ9QIJNwCvAAATAAgJ9QIJNwCvAAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8ZAAIUAAYJXxgrJACCAQAUAAYJXxgrJACCAQAuAAQKfykAAhQACAmMIuEcAF0CABQACAmMIuEcAF0CAAEuAAQKBQkKAAYAAAAA.Demonkanaka:BAAALgADCgIJAwAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgAECgUJBQAAAA==.Devinetoro:BAABLgAECn8tAAIMAAkJVQjnfQBnAQAMAAkJVQjnfQBnAQAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAIVAAkJGRcmLAD/AQAVAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn8zAAQWAAkJExrrAgBvAgAWAAkJExrrAgBvAgAXAAQJTRKTKwCBAAAYAAMJLQZdcgBzAAAAAA==.',
Do='Doree:BAAALgADCgYJBgAAAA==.Dotdotoops:BAAALgAECgEJAQAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAUJEwAZAAYQAA==.Dreadsofdeth:BAABLgAECn8VAAICAAYJixh1ngCZAQACAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJEAAAAA==.Drklhtkanaka:BAAALgAECgEJAQAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.Drustone:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8yAAIIAAgJBBKmUgCfAQAIAAgJBBKmUgCfAQAAAA==.',
Eh='Ehtar:BAAALgAECgYJBgABLgAFFAYJFwAPALEUAA==.',
Ei='Einheri:BAABLgAECn8uAAIBAAkJfxyuEABrAgABAAkJfxyuEABrAgAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgAECgYJCAAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8PAAISAAMJ/hyLIQAAAQASAAMJ/hyLIQAAAQAuAAQKfywAAhIACQkvGjYOADoCABIACQkvGjYOADoCAAAA.Enoira:BAAALgAECgEJAgAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAABLgAECn8VAAILAAYJ8BUGGQBGAQALAAYJ8BUGGQBGAQAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Et='Ethel:BAAALgAECgEJAQAAAA==.',
Ev='Evillizard:BAABLgAECn8XAAIYAAgJ2wrbOwAwAQAYAAgJ2wrbOwAwAQAAAA==.',
Ex='Exhumer:BAABLgAECn8kAAIMAAgJuSXWDAD2AgAMAAgJuSXWDAD2AgAAAA==.',
Fa='Faffard:BAABLgAECn8cAAIFAAYJrxEyegA+AQAFAAYJrxEyegA+AQABLgAECgkJOAAaAAQJAA==.Fame:BAAALgAFFAEJAQABLgAFFAYJFwAYAPkXAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgQJBAAAAA==.',
Fe='Fearbilly:BAAALgAECgQJBwAAAA==.Felbilly:BAAALgADCgUJBQAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAABLgAECn8XAAMVAAYJzwIzkACKAAAVAAYJzwIzkACKAAAbAAEJrAFZoQASAAAAAA==.',
Fl='Flap:BAACLgAFFH8XAAIYAAYJ+RfFGwBjAQAYAAYJ+RfFGwBjAQAuAAQKfxkAAxgACAlOGG4cAOQBABgACAlOGG4cAOQBABYAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fu='Furbalkanaka:BAAALgADCgEJAQAAAA==.',
Fy='Fystie:BAABLgAECn8hAAMVAAYJyBlGNQC8AQAVAAYJyBlGNQC8AQAbAAUJwAdmXQCRAAABLgAECgkJOAAaAAQJAA==.',
Ga='Galpally:BAABLgAECn8kAAIMAAcJ5xMIeQBxAQAMAAcJ5xMIeQBxAQAAAA==.Ganzar:BAAALgADCgMJBAABLgAFFAMJEAADAMMkAA==.Garin:BAAALgAECgUJBgAAAA==.',
Ge='Genma:BAAALgAECgQJBAAAAA==.Gennic:BAAALgADCgcJBwAAAA==.Gettinskins:BAAALgAECgMJAwAAAA==.',
Gi='Gishongar:BAAALgAECgcJBwAAAA==.',
Gl='Glorak:BAABLgAECn8nAAIFAAcJdgjqgQAuAQAFAAcJdgjqgQAuAQAAAA==.',
Gr='Grashen:BAABLgAECn8lAAIJAAcJARuJJgAaAgAJAAcJARuJJgAaAgAAAA==.Gravorik:BAAALgAFFAIJAwAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDwAAAA==.',
Gs='Gsm:BAABLgAECn82AAIcAAkJnRmpDgB4AgAcAAkJnRmpDgB4AgAAAA==.',
Gu='Gulritz:BAAALgAECgIJAgAAAA==.Gurlyman:BAAALgAECgUJDAAAAA==.',
Ha='Haikara:BAAALgADCgMJAwAAAA==.Hante:BAAALgADCgcJEAAAAA==.Hartmonster:BAAALgAECgQJCAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMFAAcJIQVmbQAfAQAFAAYJ0gVmbQAfAQAZAAEJrwHEQgAbAAAAAA==.Hideous:BAAALgAECgQJBAAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgUJDQAAAA==.Hotspur:BAAALgAECgMJAwABLgAECggJJwAVALIVAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ia='Iaanditos:BAAALgADCgYJBgAAAA==.',
Ig='Ignath:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilisselia:BAAALgADCgcJBwAAAA==.Ilokana:BAAALgAECgMJBQAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgYJEQAAAA==.',
It='Itzbarney:BAAALgAECggJEwAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacsknight:BAAALgAECgUJBwAAAA==.Jacspally:BAABLgAECn8bAAMMAAgJChrrNwAXAgAMAAgJChrrNwAXAgAdAAEJ0AO0lwAiAAAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8hAAIeAAkJ8h8iBADOAgAeAAkJ8h8iBADOAgAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAABLgAECn8zAAIbAAgJXRXqHADUAQAbAAgJXRXqHADUAQAAAA==.Jellexy:BAABLgAECn8hAAICAAYJmQKJ/wCjAAACAAYJmQKJ/wCjAAAAAA==.',
Ji='Jimlahey:BAAALgAECgMJAwABLgAFFAUJGQACADEfAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8VAAIKAAQJMRhtIgArAQAKAAQJMRhtIgArAQAuAAQKfzEAAgoACAn5HUIWAFUCAAoACAn5HUIWAFUCAAAA.Jonnyfive:BAAALgAECgUJDwAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIFAAkJ6hdbKwAlAgAFAAkJ6hdbKwAlAgAAAA==.Kaisa:BAAALgADCgcJBwAAAA==.Kalimthor:BAAALgADCgEJAQAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAABLgAECn8dAAIMAAgJZBQKUQDLAQAMAAgJZBQKUQDLAQAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8sAAMFAAgJ8B7VBABBAgAFAAcJnyPVBABBAgAZAAYJEw3CCgBuAQAuAAQKf0EAAxkACQkiJo8CAIkDABkACQkYIo8CAIkDAAUACQkiJu0FACwDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgUJBQAAAA==.Keheo:BAAALgAECgQJCwAAAA==.',
Kh='Khandragho:BAAALgAECgYJBgAAAA==.Khaza:BAAALgAECgUJBQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kiri:BAAALgAECgEJAQABLgAECgkJKwAHAAQRAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn9PAAIEAAkJGSJOAQAlAwAEAAkJGSJOAQAlAwAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIdAAkJbRfBJgD0AQAdAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgUJDgAAAA==.Kruger:BAABLgAECn8jAAIIAAcJ+gfDmQAFAQAIAAcJ+gfDmQAFAQAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.Krzykanaka:BAAALgADCgIJAwAAAA==.',
Kt='Ktanna:BAABLgAECn8XAAIfAAcJaAjXMQDoAAAfAAcJaAjXMQDoAAAAAA==.',
Ku='Kublakhan:BAAALgAECggJDgAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwAAAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8gAAIJAAkJixxxJwAVAgAJAAkJixxxJwAVAgAAAA==.Lapras:BAEBLgAFFH8MAAIYAAUJeyZSEgDBAQAYAAUJeyZSEgDBAQAAAA==.Lateralus:BAABLgAECn8sAAIMAAkJzhj6KQBPAgAMAAkJzhj6KQBPAgAAAA==.Laureli:BAABLgAECn8bAAIBAAYJJQMAcACXAAABAAYJJQMAcACXAAAAAA==.',
Le='Leeta:BAABLgAECn8nAAIeAAgJ6RtFCgAvAgAeAAgJ6RtFCgAvAgAAAA==.Legendx:BAAALgADCgUJBwAAAA==.Letholdus:BAAALgAECggJDQAAAA==.',
Li='Lightningg:BAABLgAECn8dAAIWAAkJAAwLCQCPAQAWAAkJAAwLCQCPAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgABLgAFFAQJDAACAOwYAA==.',
Lo='Loahavemercy:BAAALgAECgEJAQAAAA==.Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgAECgUJDQAAAA==.Losoz:BAAALgAECgEJAgAAAA==.',
Lu='Lucariel:BAABLgAECn8YAAIDAAkJbxizJQBkAgADAAkJbxizJQBkAgAAAA==.Lusilsandrus:BAAALgAECgYJEwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAAALgAFFAMJBAAAAA==.Magusbilly:BAAALgADCgcJBwAAAA==.Mahoutsukai:BAABLgAECn8fAAICAAgJwwIezADyAAACAAgJwwIezADyAAAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8nAAIcAAgJDQiLRwAFAQAcAAgJDQiLRwAFAQAAAA==.',
Me='Mechaknight:BAAALgAECgUJCQAAAA==.',
Mi='Mildrik:BAABLgAECn8dAAIBAAkJKgljMACFAQABAAkJKgljMACFAQAAAA==.Miracledh:BAABLgAECn8aAAIfAAgJkiWiBQDYAgAfAAgJkiWiBQDYAgAAAA==.Mirkdrak:BAABLgAECn8dAAMYAAYJ1QlqUwDVAAAYAAYJ1QlqUwDVAAAWAAMJyQJmNgBjAAAAAA==.Misheard:BAACLgAFFH8DAAIUAAIJmBGgiwBFAAAUAAIJmBGgiwBFAAAuAAQKfzoAAhQACQnKIKwTAJsCABQACQnKIKwTAJsCAAAA.Misjudged:BAABLgAECn8UAAQYAAcJqhBMPgAlAQAYAAcJqhBMPgAlAQAWAAQJhw0dKQDWAAAXAAIJghjiQgBWAAAAAA==.Missus:BAAALgAFFAMJAwAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgQJBQAAAA==.Mizzen:BAABLgAECn8qAAMgAAkJ/R8TBgDjAgAgAAkJ/R8TBgDjAgAhAAEJawSHoQAdAAABLgAFFAYJFwAPALEUAA==.',
Mo='Mohtavius:BAABLgAECn8zAAIRAAkJlhlrCQBUAgARAAkJlhlrCQBUAgAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn84AAIaAAkJBAmMEAAtAQAaAAkJBAmMEAAtAQAAAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Mu='Mulnier:BAAALgADCgkJCgAAAA==.Munkìe:BAAALgAECgUJDQABLgAECgkJNgAcAJ0ZAA==.Muura:BAABLgAECn8hAAIDAAkJEA1+nwAjAQADAAkJEA1+nwAjAQAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJEgAAAA==.',
Na='Nakavelli:BAAALgAECgEJAQAAAA==.Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8tAAIJAAkJZR1UDQDhAgAJAAkJZR1UDQDhAgAAAA==.Nattal:BAAALgADCgUJBQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJDAAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAgJKgAXAOIdAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Ot='Otwin:BAAALgAECgUJEwAAAA==.',
Pa='Pahuum:BAAALgAECgUJDAAAAA==.Paimon:BAABLgAECn8XAAILAAcJcRwhDgDVAQALAAcJcRwhDgDVAQABLgAFFAYJFwAYAPkXAA==.Paintrainn:BAABLgAECn8XAAIJAAgJdgFGlQCWAAAJAAgJdgFGlQCWAAAAAA==.Palewhiteman:BAABLgAECn8hAAIdAAgJ5hkBGgAqAgAdAAgJ5hkBGgAqAgAAAA==.Palleigh:BAABLgAECn8eAAIdAAgJ+wzSMQCEAQAdAAgJ+wzSMQCEAQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8nAAIVAAgJshUWLADvAQAVAAgJshUWLADvAQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8iAAIFAAkJGBnNJABEAgAFAAkJGBnNJABEAgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Po='Poondor:BAABLgAECn8XAAIdAAgJ0hPbIwDcAQAdAAgJ0hPbIwDcAQAAAA==.',
Pr='Predaturd:BAAALgAECggJBQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Qi='Qindere:BAABLgAECn8VAAICAAcJmQMA/gD/AAACAAcJmQMA/gD/AAAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn9EAAIFAAkJPhoqIABbAgAFAAkJPhoqIABbAgAAAA==.Rakshaman:BAAALgAECgYJEAAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgYJCwABLgAFFAMJEAADAMMkAA==.',
Re='Reihino:BAAALgAECgUJBQAAAA==.Resbak:BAABLgAECn8UAAIbAAgJogzZMABLAQAbAAgJogzZMABLAQAAAA==.Resiaus:BAABLgAECn89AAIXAAkJyRxTBADiAgAXAAkJyRxTBADiAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECgYJDgAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Robinho:BAAALgAECgcJDQAAAA==.Rocketabu:BAAALgAECgMJBAAAAA==.Roctheist:BAABLgAECn8UAAMPAAYJEAbHSAC8AAAPAAYJEAbHSAC8AAAiAAYJEwa6SwCkAAAAAA==.Rocthoeb:BAABLgAECn80AAIRAAkJxRH/EQDoAQARAAkJxRH/EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAABLgAECn8qAAMjAAkJOSOrAQAbAwAjAAkJOSOrAQAbAwAVAAEJ8AQC8gAaAAAAAA==.',
Sa='Saeris:BAAALgAECgUJBwAAAA==.Saintalpha:BAEALgAECgEJAQABLgAECggJFQAHAJkTAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFQAHAJkTAA==.Saintkhal:BAEALgAECgQJDQABLgAECggJFQAHAJkTAA==.Saintmedicus:BAEBLgAECn8VAAMHAAgJmRM6NQAzAQAHAAUJZBc6NQAzAQAPAAMJ0w0qXACYAAAAAA==.Saintshammy:BAABLgAFFH8FAAIJAAMJWxU5QgDLAAAJAAMJWxU5QgDLAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Saki:BAAALgADCgUJBQAAAA==.Sanctor:BAABLgAECn8dAAIdAAcJeyJ0EgB/AgAdAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Saraya:BAABLgAECn8WAAIdAAgJxBcSHQAPAgAdAAgJxBcSHQAPAgAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8hAAIHAAkJYh3yBwDuAgAHAAkJYh3yBwDuAgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shanoodles:BAAALgAECgQJBAAAAA==.Shibaryotaro:BAAALgAECgEJAQAAAA==.Shiftee:BAAALgAECgQJBAABLgAECgcJHAAFABsWAA==.Shinstabber:BAABLgAECn8hAAITAAkJARQ+EgDeAQATAAkJARQ+EgDeAQAAAA==.Shivantis:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Shruggie:BAABLgAECn8pAAMfAAgJAhQoFwC8AQAfAAgJAhQoFwC8AQAUAAIJJwT/CQEwAAAAAA==.',
Si='Silven:BAAALgAECgYJDgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8YAAIKAAgJSxtjFgBUAgAKAAgJSxtjFgBUAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8cAAIFAAcJGxZxLwD0AQAFAAcJGxZxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgAECgYJCQAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8tAAMZAAkJuwdpEgAqAQAkAAgJKATsKwA/AQAZAAkJnAdpEgAqAQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAJADYRAA==.Starlie:BAAALgAECgUJDgAAAA==.Stormstrike:BAAALgAECgcJBgAAAA==.Stratacaster:BAABLgAECn8WAAIIAAcJyQIyzgCuAAAIAAcJyQIyzgCuAAAAAA==.Strawberry:BAAALgAECgUJDgAAAA==.Stuckinwell:BAACLgAFFH8FAAMIAAIJkBjuNQCnAAAIAAIJGBDuNQCnAAAaAAEJlBbOIQBNAAAuAAQKfxsAAwgACQn6GsEzAD0CAAgACAnpFsEzAD0CABoABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAIVAAIJhh6QFQC3AAAVAAIJhh6QFQC3AAABLgAFFAgJKgAXAOIdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDwABLgAECgkJQwATAJUZAA==.Synpathi:BAEALgADCgEJAQABLgAECgcJVAAlANITAA==.Synsyn:BAEBLgAECn9UAAMlAAcJ0hNoDACEAQAlAAcJ0hNoDACEAQAIAAYJ0Am6qgDoAAAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8eAAICAAkJfQ1HiQC/AQACAAkJfQ1HiQC/AQAAAA==.',
Te='Teanfists:BAAALgAECgYJCgAAAA==.Temna:BAABLgAECn82AAIMAAkJfSMmBgA6AwAMAAkJfSMmBgA6AwAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAABLgAECn8bAAIFAAYJABqtWgCIAQAFAAYJABqtWgCIAQAAAA==.Thespaniard:BAABLgAECn8dAAIPAAcJPhkXJwCMAQAPAAcJPhkXJwCMAQAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAABLgAECn8WAAIeAAgJlQmSLADpAAAeAAgJlQmSLADpAAAAAA==.Tinbasher:BAAALgAECgUJCgAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAABLgAECn8eAAMVAAkJ7gnjRgBqAQAVAAkJ7gnjRgBqAQAbAAEJ5QyyhgAyAAAAAA==.Tricky:BAAALgAECgUJDgAAAA==.Triviousox:BAABLgAECn8XAAIMAAcJkw/yjABMAQAMAAcJkw/yjABMAQAAAA==.Tryxx:BAAALgADCgUJBQAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAFFAUJDQAmAPkXAA==.Twotvmage:BAABLgAECn8uAAMCAAkJJB0aJwB4AgACAAkJJB0aJwB4AgAmAAEJIA38FQAuAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Unglued:BAAALgAECgYJBgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJDQABLgAECgkJNwAIAA8cAA==.',
Up='Uplift:BAABLgAFFH8FAAIgAAQJXRjEDwA2AQAgAAQJXRjEDwA2AQABLgAFFAgJHgACAJsbAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Va='Vale:BAAALgAECggJCAAAAA==.Valkky:BAABLgAECn80AAMnAAkJzBQ1CADlAQAnAAkJIhQ1CADlAQAUAAQJOA0VowDOAAAAAA==.Valky:BAAALgADCgQJBAABLgAECgkJNAAnAMwUAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn8rAAMHAAkJBBHZHgDJAQAHAAkJywzZHgDJAQAiAAcJiw9XMwAqAQAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECggJEAABLgAECgkJKwAHAAQRAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn82AAIFAAkJKR6rDwDKAgAFAAkJKR6rDwDKAgAAAA==.Vessna:BAABLgAECn8dAAICAAYJxAU53ADaAAACAAYJxAU53ADaAAABLgAECgYJHQAYANUJAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAABLgAECn8bAAIjAAcJliBqCAA2AgAjAAcJliBqCAA2AgAAAA==.',
Vm='Vmro:BAAALgADCgYJFgAAAA==.',
Vo='Voras:BAAALgAECgYJEQAAAA==.Vorttex:BAAALgAECgUJDAAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHAAYAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8nAAInAAgJBRm0BwDyAQAnAAgJBRm0BwDyAQAAAA==.',
Wh='Whiskeyrick:BAAALgAECgQJBAAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAwAAAA==.Winters:BAAALgAECgEJAQAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIPAAgJ4RsHEQB4AgAPAAgJ4RsHEQB4AgAAAA==.',
Xi='Xivago:BAAALgAECgUJBQAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAACLgAFFH8HAAIkAAMJcQgcIADCAAAkAAMJcQgcIADCAAAuAAQKfxYAAyQACAkDDu0iAIEBACQACAkDDu0iAIEBABkABAmABINqAJQAAAAA.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yo='Yoshino:BAAALgAECgUJBQABLgAECgYJFAACABEHAA==.',
Yu='Yuzuriha:BAAALgAECgYJDwAAAA==.',
Za='Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgAECgQJBQAAAA==.',
Zo='Zophier:BAAALgAECgQJBQAAAA==.Zouk:BAAALgAECgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAABLgAECn8YAAIZAAcJhwx5FAAOAQAZAAcJhwx5FAAOAQAAAA==.',
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
