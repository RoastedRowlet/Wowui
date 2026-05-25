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

local lookup = {'Warrior-Fury','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Warrior-Protection','Rogue-Subtlety','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Destruction','Druid-Balance','DeathKnight-Unholy','Shaman-Elemental','Druid-Guardian','Priest-Discipline','DeathKnight-Frost','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Druid-Feral','DeathKnight-Blood','Hunter-Survival','Warlock-Affliction','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAABLgAECn8VAAIBAAcJYxBBPQAoAQABAAcJYxBBPQAoAQAAAA==.Akusenshi:BAABLgAECn8UAAIBAAcJOxDSLwBoAQABAAcJOxDSLwBoAQAAAA==.',
Al='Alarr:BAAALgAECgYJBwABLgAFFAMJBwACAPcYAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAAALgAECgYJEwAAAA==.Alexi:BAAALgADCgcJCwAAAA==.Alivis:BAEALgAECgQJBAABLgAECggJJgADAJEgAA==.Alzith:BAAALgAECgQJBQABLgAECggJCQAEAAAAAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgADCgMJBgAEAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAgJNAAFAGYlAA==.',
Ap='Apexalpha:BAAALgAECgQJCAAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgAECgMJAwAAAA==.Arold:BAABLgAECn8iAAIGAAgJ0RJgSQCnAQAGAAgJ0RJgSQCnAQAAAA==.',
As='Asylia:BAACLgAFFH8KAAIHAAQJNhGCCQA5AQAHAAQJNhGCCQA5AQAuAAQKfxcAAgcACAlLGy4hABcCAAcACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8aAAIIAAYJVw0TRgD6AAAIAAYJVw0TRgD6AAAAAA==.',
Au='Aurelliae:BAABLgAECn8WAAIDAAgJtBXTQAC0AQADAAgJtBXTQAC0AQAAAA==.',
Av='Avesiren:BAABLgAECn8dAAIJAAYJQxXwGAAmAQAJAAYJQxXwGAAmAQAAAA==.',
Ay='Ayidá:BAAALgAECgUJDAAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECgcJDAAAAA==.Babymamaa:BAAALgAECgMJBQAAAA==.Babymuffins:BAABLgAECn8aAAIKAAYJbiHLTQC/AQAKAAYJbiHLTQC/AQAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAAALgAECgYJBwAAAA==.Beklee:BAAALgADCgUJBQAAAA==.Belanda:BAAALgAECgMJBQAAAA==.Belgord:BAAALgAECgUJCQAAAA==.Belin:BAAALgADCgkJFgAAAA==.Belmond:BAAALgAECgQJCAAAAA==.',
Bl='Blackmill:BAAALgAECgYJDAAAAA==.Blayrog:BAABLgAECn8pAAICAAgJuBQbXQCrAQACAAgJuBQbXQCrAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8vAAMLAAkJGBhGCgAdAgALAAkJzRdGCgAdAgABAAYJ/RDSUQBiAQABLgAFFAYJFgAMAD0TAA==.Bobbyknocker:BAAALgAECgcJBwAAAA==.Bolf:BAAALgAECgUJEgAAAA==.Boombaaby:BAABLgAECn8cAAIDAAYJpQyrfgATAQADAAYJpQyrfgATAQAAAA==.Bootzee:BAABLgAECn8ZAAIHAAcJpxRoNgCmAQAHAAcJpxRoNgCmAQAAAA==.',
Br='Brewglaive:BAAALgAECgEJAgAAAA==.Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAABLgAECn8TAAIMAAYJpwRKSADAAAAMAAYJpwRKSADAAAAAAA==.Brunhilian:BAAALgAECgUJCQAAAA==.',
Bu='Buckmaster:BAAALgADCggJDAAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAABLgAECn8aAAIBAAYJMwc2UwDTAAABAAYJMwc2UwDTAAAAAA==.Calada:BAAALgAECgUJCwAAAA==.Carbion:BAAALgADCgkJCQAAAA==.',
Ce='Cedarnia:BAAALgADCggJBwAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAQAEAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8eAAIHAAkJOxbIGABXAgAHAAkJOxbIGABXAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJCwAAAA==.',
Co='Corrynn:BAAALgAECgcJEgAAAA==.',
Cr='Cribbage:BAACLgAFFH8FAAINAAMJTB42EAACAQANAAMJTB42EAACAQAuAAQKfycAAw0ACAljIlcHAGsCAA0ACAljIlcHAGsCAAsAAQnMGl5VAEgAAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgADCggJDwAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgUJEwAAAA==.',
Cy='Cynosure:BAABLgAECn8xAAIOAAkJvRmZDAA2AgAOAAkJvRmZDAA2AgAAAA==.Cytronsneak:BAAALgAECgMJBAAAAA==.',
Da='Dabb:BAAALgADCggJDgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgUJDQAAAA==.Daliå:BAAALgADCgYJBgAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8cAAIGAAcJmQu4dwA0AQAGAAcJmQu4dwA0AQAAAA==.Darkheaven:BAABLgAECn8bAAIKAAgJegingQBLAQAKAAgJegingQBLAQAAAA==.Darkkanaka:BAAALgADCgEJAQAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAAALgAECggJEAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8SAAIPAAUJ9xqEKQBBAQAPAAUJ9xqEKQBBAQAuAAQKfykAAg8ACAmMIgkZAGICAA8ACAmMIgkZAGICAAEuAAQKBQkKAAQAAAAA.Demonkanaka:BAAALgADCgEJAQAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgADCggJCgAAAA==.Devinetoro:BAABLgAECn8dAAIKAAcJPgcKpQAOAQAKAAcJPgcKpQAOAQAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAIQAAkJGRcmLAD/AQAQAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn8jAAQRAAgJFRghBQDxAQARAAgJFRghBQDxAQASAAQJTRLwJwCAAAATAAMJLQbSZQB0AAAAAA==.',
Do='Doree:BAAALgADCgYJBgAAAA==.Dotdotoops:BAAALgAECgEJAQAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAUJDwAUALkKAA==.Dreadsofdeth:BAABLgAECn8VAAICAAYJixh1ngCZAQACAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJDwAAAA==.Drklhtkanaka:BAAALgADCgYJBgAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8mAAIGAAgJKxC6UACSAQAGAAgJKxC6UACSAQAAAA==.',
Ei='Einheri:BAABLgAECn8rAAIBAAgJShqLGAAGAgABAAgJShqLGAAGAgAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgAECgYJBgAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8NAAIOAAMJ/hz+GQATAQAOAAMJ/hz+GQATAQAuAAQKfywAAg4ACQkvGkkLAEwCAA4ACQkvGkkLAEwCAAAA.Enoira:BAAALgAECgEJAgAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAAALgAECgUJDgAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Et='Ethel:BAAALgAECgEJAQAAAA==.',
Ev='Evillizard:BAABLgAECn8WAAITAAcJJwpXPwAFAQATAAcJJwpXPwAFAQAAAA==.',
Ex='Exhumer:BAABLgAECn8eAAIKAAYJTyYDLQArAgAKAAYJTyYDLQArAgAAAA==.',
Fa='Faffard:BAABLgAECn8VAAIDAAYJzgrZhwD+AAADAAYJzgrZhwD+AAABLgAECgkJNgAVAOcIAA==.Fame:BAAALgAFFAEJAQABLgAFFAUJFQATAFEZAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgEJAQAAAA==.',
Fe='Fearbilly:BAAALgAECgQJBwAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAAALgAECgYJEAAAAA==.',
Fl='Flap:BAACLgAFFH8VAAITAAUJURmiHgAjAQATAAUJURmiHgAjAQAuAAQKfxkAAxMACAlOGG4cAOQBABMACAlOGG4cAOQBABEAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fu='Furbalkanaka:BAAALgADCgEJAQAAAA==.',
Fy='Fystie:BAABLgAECn8aAAMQAAYJ3RhSMwCsAQAQAAYJ3RhSMwCsAQAWAAUJwAcdUwCRAAABLgAECgkJNgAVAOcIAA==.',
Ga='Galpally:BAABLgAECn8ZAAIKAAcJkxL2cgBoAQAKAAcJkxL2cgBoAQAAAA==.Ganzar:BAAALgADCgMJBAABLgAFFAMJCgAXAFEkAA==.Garin:BAAALgAECgUJBgAAAA==.',
Ge='Gennic:BAAALgADCgcJBwAAAA==.Gettinskins:BAAALgADCgEJAQAAAA==.',
Gi='Gishongar:BAAALgADCgkJCQAAAA==.',
Gl='Glorak:BAABLgAECn8eAAIDAAcJJQYJfQAWAQADAAcJJQYJfQAWAQAAAA==.',
Gr='Grashen:BAABLgAECn8eAAIHAAYJsh0GKADwAQAHAAYJsh0GKADwAQAAAA==.Gravorik:BAAALgAFFAEJAQAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDgAAAA==.',
Gs='Gsm:BAABLgAECn8mAAIYAAgJWxOTIQCqAQAYAAgJWxOTIQCqAQAAAA==.',
Gu='Gulritz:BAAALgAECgEJAQAAAA==.Gurlyman:BAAALgAECgMJAwAAAA==.',
Ha='Hante:BAAALgADCgcJCwAAAA==.Hartmonster:BAAALgAECgQJCAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMDAAcJIQVmbQAfAQADAAYJ0gVmbQAfAQAUAAEJrwHdOwAcAAAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgMJBAAAAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ia='Iaanditos:BAAALgADCgYJBgAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilokana:BAAALgAECgEJAgAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgYJCwAAAA==.',
It='Itzbarney:BAAALgAECgYJDAAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacspally:BAAALgAECggJEgAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8gAAIZAAgJISEGBQCNAgAZAAgJISEGBQCNAgAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAABLgAECn8kAAIWAAcJ8xDwKwBHAQAWAAcJ8xDwKwBHAQAAAA==.Jellexy:BAABLgAECn8aAAICAAYJTwIv8QCYAAACAAYJTwIv8QCYAAAAAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8OAAIIAAQJchT1HAANAQAIAAQJchT1HAANAQAuAAQKfzAAAggACAk1HVwUAD4CAAgACAk1HVwUAD4CAAAA.Jonnyfive:BAAALgAECgMJBgAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIDAAkJ6hejIgAvAgADAAkJ6hejIgAvAgAAAA==.Kaisa:BAAALgADCgcJBwAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAAALgAECgYJEAAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8rAAMDAAgJ8B6eAQBWAgADAAcJnyOeAQBWAgAUAAYJEw3CCgBuAQAuAAQKf0EAAwMACQkiJskDADoDABQACQkYIo8CAIkDAAMACQkiJskDADoDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgUJBAAAAA==.Keheo:BAAALgAECgQJBwAAAA==.',
Kh='Khandragho:BAAALgAECgEJAQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kiri:BAAALgADCgYJBgABLgAECggJIQAaALcQAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn89AAIbAAkJJBu0AwBkAgAbAAkJJBu0AwBkAgAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIcAAkJbRfBJgD0AQAcAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgMJBQAAAA==.Kruger:BAABLgAECn8hAAIGAAcJ6gf3iwANAQAGAAcJ6gf3iwANAQAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.Krzykanaka:BAAALgADCgIJAgAAAA==.',
Kt='Ktanna:BAAALgAECgYJEAAAAA==.',
Ku='Kublakhan:BAAALgAECggJCwAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAUJGwAJAFEgAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8gAAIHAAkJixw9IQAaAgAHAAkJixw9IQAaAgAAAA==.Lapras:BAEALgAFFAkJAwAAAA==.Lateralus:BAABLgAECn8dAAIKAAgJow7iaQB7AQAKAAgJow7iaQB7AQAAAA==.Laureli:BAABLgAECn8UAAIBAAYJxgLLZQCQAAABAAYJxgLLZQCQAAAAAA==.',
Le='Leeta:BAABLgAECn8aAAIZAAYJ/xudEgCJAQAZAAYJ/xudEgCJAQAAAA==.Legendx:BAAALgADCgUJBwAAAA==.',
Li='Lightningg:BAABLgAECn8cAAIRAAgJmAx4CQBrAQARAAgJmAx4CQBrAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgABLgAFFAMJBwACAPcYAA==.',
Lo='Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgAECgMJBQAAAA==.Losoz:BAAALgAECgEJAgAAAA==.',
Lu='Lucariel:BAAALgAECggJCQAAAA==.Lusilsandrus:BAAALgAECgYJEwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAAALgAECggJCQAAAA==.Mahoutsukai:BAABLgAECn8ZAAICAAgJmQKKuwDzAAACAAgJmQKKuwDzAAAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8aAAIYAAYJ4wdzUwC7AAAYAAYJ4wdzUwC7AAAAAA==.',
Me='Mechaknight:BAAALgAECgUJCAAAAA==.',
Mi='Mildrik:BAABLgAECn8cAAIBAAgJYQlqNABSAQABAAgJYQlqNABSAQAAAA==.Miracledh:BAABLgAECn8ZAAIdAAgJkiX7AwDlAgAdAAgJkiX7AwDlAgAAAA==.Mirkdrak:BAABLgAECn8WAAMTAAYJYgeHVACzAAATAAYJYgeHVACzAAARAAMJyQJmNgBjAAAAAA==.Misheard:BAACLgAFFH8DAAIPAAIJmBEAewBHAAAPAAIJmBEAewBHAAAuAAQKfzYAAg8ACQl6H+MTAIcCAA8ACQl6H+MTAIcCAAAA.Misjudged:BAABLgAECn8UAAQTAAcJqhChNgAsAQATAAcJqhChNgAsAQARAAQJhw0dKQDWAAASAAIJghjiQgBWAAAAAA==.Missus:BAAALgAECggJDwAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgQJBQAAAA==.Mizzen:BAABLgAECn8hAAMeAAcJ4RuuHwCIAQAeAAcJ4RuuHwCIAQAfAAEJawQblAAdAAABLgAFFAYJFgAMAD0TAA==.',
Mo='Mohtavius:BAABLgAECn8jAAINAAgJhxWDEgCaAQANAAgJhxWDEgCaAQAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn82AAIVAAkJ5wjTDQA1AQAVAAkJ5wjTDQA1AQAAAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Ms='Msboba:BAAALgAECgYJCwAAAA==.',
Mu='Mulnier:BAAALgADCgkJBQAAAA==.Munkìe:BAAALgAECgQJBAABLgAECggJJgAYAFsTAA==.Muura:BAABLgAECn8fAAIXAAkJcAvblQAVAQAXAAkJcAvblQAVAQAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJEgAAAA==.',
Na='Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8oAAIHAAgJ7xwgEwCIAgAHAAgJ7xwgEwCIAgAAAA==.Nattal:BAAALgADCgUJBQAAAA==.Nausica:BAAALgAECggJBQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJCgAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAcJIQASAFUeAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAAEAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Ot='Otwin:BAAALgAECgQJCgAAAA==.',
Pa='Pahuum:BAAALgAECgMJBQAAAA==.Paimon:BAAALgAECgcJEAABLgAFFAUJFQATAFEZAA==.Paintrainn:BAAALgAECgcJEAAAAA==.Palewhiteman:BAABLgAECn8hAAIcAAgJ5hltFgAwAgAcAAgJ5hltFgAwAgAAAA==.Palleigh:BAAALgAECggJEQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8aAAIQAAYJSxflOgCHAQAQAAYJSxflOgCHAQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8hAAIDAAgJ0xkQKwAHAgADAAgJ0xkQKwAHAgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Po='Poondor:BAABLgAECn8VAAIcAAgJIRI5JAC+AQAcAAgJIRI5JAC+AQAAAA==.Poplocndrop:BAAALgAECgcJDwAAAA==.',
Pr='Predaturd:BAAALgAECggJBQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Qi='Qindere:BAAALgAECgcJEwAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn8/AAIDAAkJIhmYHQBKAgADAAkJIhmYHQBKAgAAAA==.Rakshaman:BAAALgAECgUJBQAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgYJCAABLgAFFAMJCgAXAFEkAA==.',
Re='Reihino:BAAALgADCgcJCgAAAA==.Resbak:BAAALgAECggJDwAAAA==.Resiaus:BAABLgAECn88AAISAAkJyRzMAwDjAgASAAkJyRzMAwDjAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECgYJCgAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Rocketabu:BAAALgAECgMJBAAAAA==.Roctheist:BAABLgAECn8UAAMMAAYJEAbHSAC8AAAMAAYJEAbHSAC8AAAFAAYJEwbvQwCyAAAAAA==.Rocthoeb:BAABLgAECn80AAINAAkJxRH/EQDoAQANAAkJxRH/EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAABLgAECn8mAAMgAAkJHyEtAgDtAgAgAAkJHyEtAgDtAgAQAAEJ8ARN3wAaAAAAAA==.',
Sa='Saeris:BAAALgAECgMJAwAAAA==.Saintalpha:BAEALgAECgEJAQABLgAECggJFAAaAJkTAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFAAaAJkTAA==.Saintkhal:BAEALgAECgQJCQABLgAECggJFAAaAJkTAA==.Saintmedicus:BAEBLgAECn8UAAMaAAgJmRM2LgA5AQAaAAUJZBc2LgA5AQAMAAMJ0w2IUACbAAAAAA==.Saintshammy:BAABLgAFFH8FAAIHAAMJWxVOMgDkAAAHAAMJWxVOMgDkAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Sanctor:BAABLgAECn8dAAIcAAcJeyJ0EgB/AgAcAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Saraya:BAABLgAECn8UAAIcAAgJxBclGQAWAgAcAAgJxBclGQAWAgAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8gAAIaAAgJjh1RCgCiAgAaAAgJjh1RCgCiAgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shiftee:BAAALgAECgQJBAABLgAECgcJHAADABsWAA==.Shinstabber:BAABLgAECn8gAAIhAAgJ+hQpEwCvAQAhAAgJ+hQpEwCvAQAAAA==.Shivantis:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwAEAAAAAA==.Shruggie:BAABLgAECn8eAAMdAAcJlQ/JIQAvAQAdAAcJlQ/JIQAvAQAPAAIJJwR/7gAxAAAAAA==.',
Si='Silven:BAAALgAECgYJCgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgADCgIJAgAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8YAAIIAAgJSxtkEgBUAgAIAAgJSxtkEgBUAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8cAAIDAAcJGxZxLwD0AQADAAcJGxZxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgAECgUJCAAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8pAAMUAAkJuQfJDwA3AQAiAAgJ8wOtJwBAAQAUAAkJmgfJDwA3AQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAHADYRAA==.Starlie:BAAALgAECgUJCgAAAA==.Stratacaster:BAAALgAECgYJEAAAAA==.Strawberry:BAAALgAECgUJCwAAAA==.Stuckinwell:BAACLgAFFH8FAAMGAAIJkBjuNQCnAAAGAAIJGBDuNQCnAAAVAAEJlBb2GwBNAAAuAAQKfxsAAwYACQn6GsEzAD0CAAYACAnpFsEzAD0CABUABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAIQAAIJhh6QFQC3AAAQAAIJhh6QFQC3AAABLgAFFAcJIQASAFUeAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDwABLgAECggJMAAhAIoWAA==.Synpathi:BAAALgADCgEJAQAAAA==.Synsyn:BAABLgAECn8ZAAMjAAYJWgeNGgCiAAAGAAYJSwciqwDUAAAjAAQJfAaNGgCiAAAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8dAAICAAkJaw1HiQC/AQACAAkJaw1HiQC/AQAAAA==.',
Te='Teanfists:BAAALgAECgYJCgAAAA==.Temna:BAABLgAECn8mAAIKAAgJCSESFwCaAgAKAAgJCSESFwCaAgAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAABLgAECn8UAAIDAAUJiBn0bwAyAQADAAUJiBn0bwAyAQAAAA==.Thespaniard:BAABLgAECn8cAAIMAAcJPhmUIQCSAQAMAAcJPhmUIQCSAQAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAAALgAECggJEQAAAA==.Tinbasher:BAAALgAECgUJBwAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAAALgAECggJEgAAAA==.Tricky:BAAALgAECgQJBQAAAA==.Triviousox:BAAALgAECgYJEAAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAFFAQJCwACAHkTAA==.Twotvmage:BAABLgAECn8uAAMCAAkJJB3qHwCEAgACAAkJJB3qHwCEAgAkAAEJIA1hEgAxAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Unglued:BAAALgAECgYJBgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJDQABLgAECgkJNwAGAA8cAA==.',
Up='Uplift:BAABLgAFFH8FAAIeAAQJXRhBCwBDAQAeAAQJXRhBCwBDAQABLgAFFAcJEwACAPcZAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Va='Valkky:BAABLgAECn8kAAMlAAgJdQ8hDgBBAQAlAAgJFg4hDgBBAQAPAAQJOA0VowDOAAAAAA==.Valky:BAAALgADCgQJBAABLgAECggJJAAlAHUPAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn8hAAMaAAgJtxDKLQA8AQAaAAYJtA3KLQA8AQAFAAcJAA7hMgAXAQAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECgMJAwABLgAECggJIQAaALcQAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn8mAAIDAAgJSxvnKgAIAgADAAgJSxvnKgAIAgAAAA==.Vessna:BAABLgAECn8WAAICAAUJ1gRX5gCsAAACAAUJ1gRX5gCsAAABLgAECgYJFgATAGIHAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAABLgAECn8XAAIgAAcJyB9jBwAwAgAgAAcJyB9jBwAwAgAAAA==.',
Vm='Vmro:BAAALgADCgYJEQAAAA==.',
Vo='Voras:BAAALgAECgYJEQAAAA==.Vorttex:BAAALgAECgIJAwAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHAATAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8aAAIlAAYJpRt4CwB4AQAlAAYJpRt4CwB4AQAAAA==.',
Wh='Whiskeyrick:BAAALgADCgMJAwAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAgAAAA==.Winters:BAAALgADCggJCAAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIMAAgJ4RsHEQB4AgAMAAgJ4RsHEQB4AgAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAABLgAFFH8HAAIiAAMJcQggGgDWAAAiAAMJcQggGgDWAAAAAA==.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yo='Yoshino:BAAALgADCggJCAABLgAECgUJCQAEAAAAAA==.',
Yu='Yuzuriha:BAAALgAECgYJDwAAAA==.',
Za='Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgAECgEJAQAAAA==.',
Zo='Zophier:BAAALgAECgEJAQAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAAALgAECgcJEQAAAA==.',
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
