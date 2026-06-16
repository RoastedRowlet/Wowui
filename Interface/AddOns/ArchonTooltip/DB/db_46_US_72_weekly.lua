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

local lookup = {'Warrior-Fury','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Rogue-Assassination','Warrior-Arms','Priest-Shadow','Rogue-Outlaw','Rogue-Subtlety','Warrior-Protection','DeathKnight-Blood','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Destruction','Druid-Balance','Paladin-Holy','Druid-Guardian','Priest-Discipline','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Druid-Feral','Hunter-Survival','Warlock-Affliction','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ab='Abugarcia:BAAALgAECgEJAgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAABLgAECn8YAAIBAAcJhxBARgArAQABAAcJhxBARgArAQAAAA==.Akusenshi:BAABLgAECn8UAAIBAAcJOxAJOQBhAQABAAcJOxAJOQBhAQAAAA==.',
Al='Alarr:BAAALgAECgYJBwABLgAFFAQJDgACAOwYAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAABLgAECn8hAAMDAAgJ0xj6PwABAgADAAgJ0xj6PwABAgAEAAEJxxAEOQAzAAAAAA==.Alexi:BAAALgADCgkJCwAAAA==.Alivis:BAEALgAECgQJBAABLgAECgkJMAAFAGkgAA==.Alzith:BAAALgAECgQJBQABLgAECgkJIQADAI0cAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAkJPQAHAFclAA==.Animocity:BAAALgAECgIJAgAAAA==.',
Ap='Apexalpha:BAAALgAECgQJCAAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgAECgcJCgAAAA==.Arold:BAABLgAECn8lAAIIAAkJRhbVMgAMAgAIAAkJRhbVMgAMAgAAAA==.',
As='Asylia:BAACLgAFFH8KAAIJAAQJNhGCCQA5AQAJAAQJNhGCCQA5AQAuAAQKfxcAAgkACAlLGy4hABcCAAkACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8jAAIKAAgJqg4RQABmAQAKAAgJqg4RQABmAQAAAA==.',
Au='Aurelliae:BAABLgAECn8WAAIFAAgJtBXNUgCmAQAFAAgJtBXNUgCmAQAAAA==.',
Av='Avesiren:BAABLgAECn8pAAILAAcJLhJEGgBDAQALAAcJLhJEGgBDAQAAAA==.',
Ax='Axxion:BAAALgADCgYJBgAAAA==.',
Ay='Ayidá:BAAALgAECgcJEgAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECgkJEQAAAA==.Babymamaa:BAAALgAECgUJEwAAAA==.Babymuffins:BAABLgAECn8oAAIMAAgJqB9lIgB7AgAMAAgJqB9lIgB7AgAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAABLgAECn8UAAINAAgJYwm6RgAUAQANAAgJYwm6RgAUAQAAAA==.Beklee:BAAALgADCgYJBgAAAA==.Belanda:BAAALgAECgUJCgAAAA==.Belgord:BAAALgAECgYJEwAAAA==.Belin:BAAALgADCgkJFgAAAA==.Bellyn:BAAALgAECggJCAAAAA==.Belmond:BAAALgAECgQJCAAAAA==.Belzac:BAAALgAECgMJAwAAAA==.Bemuse:BAAALgADCgcJDAAAAA==.',
Bl='Blackmill:BAABLgAECn8UAAIOAAgJZBoRBQAuAgAOAAgJZBoRBQAuAgAAAA==.Blayrog:BAABLgAECn8pAAICAAgJuBRgbQCcAQACAAgJuBRgbQCcAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8vAAMPAAkJGBhuDQAOAgAPAAkJzRduDQAOAgABAAYJ/RDSUQBiAQABLgAFFAcJGAAQADEUAA==.Bobamood:BAAALgAECgIJAgAAAA==.Bobbyknocker:BAAALgAECgcJCAAAAA==.Bolf:BAABLgAECn8aAAMRAAYJ9AtsEQDyAAARAAYJ9AtsEQDyAAASAAEJAAD2ZwAAAAAAAA==.Boneharnen:BAAALgAECgYJDAAAAA==.Boombaaby:BAABLgAECn8pAAIFAAgJCw4ZXACMAQAFAAgJCw4ZXACMAQAAAA==.Bootzee:BAABLgAECn8gAAIJAAcJbxvgJwAcAgAJAAcJbxvgJwAcAgAAAA==.',
Br='Brewglaive:BAAALgAECgEJAwAAAA==.Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAABLgAECn8lAAIQAAkJ2ghfLgBmAQAQAAkJ2ghfLgBmAQAAAA==.Brunhilian:BAAALgAECgUJDQAAAA==.',
Bs='Bsê:BAAALgAECgEJAQAAAA==.',
Bu='Buckmaster:BAAALgAECgUJCgAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAABLgAECn8oAAIBAAgJXQdBRgArAQABAAgJXQdBRgArAQAAAA==.Calada:BAABLgAECn8XAAIHAAYJCQMgUQCVAAAHAAYJCQMgUQCVAAAAAA==.Callypso:BAAALgAECgYJBgABLgAECggJIwAKAKoOAA==.Carbion:BAAALgADCgkJCQAAAA==.',
Ce='Cedarnia:BAAALgADCggJBwAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAgAGAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8eAAIJAAkJOxYxHwBRAgAJAAkJOxYxHwBRAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJDgAAAA==.',
Co='Corrynn:BAAALgAECgcJEgAAAA==.',
Cr='Cribbage:BAACLgAFFH8JAAITAAMJwB5lFgDjAAATAAMJwB5lFgDjAAAuAAQKfykAAxMACQlJIksFAMICABMACQlJIksFAMICAA8AAQnMGhVrAEYAAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgADCggJDwAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgUJEwAAAA==.',
Cy='Cynosure:BAABLgAECn8xAAISAAkJvRmlEAAiAgASAAkJvRmlEAAiAgABLgAFFAEJAwAGAAAAAA==.Cytronsneak:BAAALgAECgUJEgAAAA==.',
Da='Dabb:BAAALgADCggJDgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgUJDQAAAA==.Daela:BAAALgADCgYJBgAAAA==.Daliå:BAAALgAECgEJAQAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8jAAIIAAkJdgzsVQCaAQAIAAkJdgzsVQCaAQAAAA==.Darkheaven:BAABLgAECn8eAAIMAAkJagpWcgCGAQAMAAkJagpWcgCGAQAAAA==.Darkkanaka:BAAALgADCgEJAgAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAABLgAECn8kAAIUAAkJ/wVeKgACAQAUAAkJ/wVeKgACAQAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8ZAAIVAAYJXxggKQB7AQAVAAYJXxggKQB7AQAuAAQKfykAAhUACAmMIioeAFwCABUACAmMIioeAFwCAAEuAAQKBQkKAAYAAAAA.Demonkanaka:BAAALgADCgIJAwAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgAECgUJBQAAAA==.Devinetoro:BAABLgAECn8tAAIMAAkJVQiOgwBlAQAMAAkJVQiOgwBlAQAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAIWAAkJGRcmLAD/AQAWAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn82AAQXAAkJExoeAwBsAgAXAAkJExoeAwBsAgAYAAQJTRKfLACBAAAZAAMJLQYsdwBxAAAAAA==.',
Dk='Dklunar:BAAALgAFFAQJBAAAAA==.',
Do='Doree:BAAALgADCgYJBgAAAA==.Dotdotoops:BAAALgAECgEJAQAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAUJFwAaAGsUAA==.Dreadsofdeth:BAABLgAECn8VAAICAAYJixh1ngCZAQACAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJEAAAAA==.Drklhtkanaka:BAAALgAECgEJAQAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.Drustone:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8yAAIIAAgJBBKoVQCaAQAIAAgJBBKoVQCaAQAAAA==.',
Eh='Ehtar:BAAALgAECgYJBgABLgAFFAcJGAAQADEUAA==.',
Ei='Einheri:BAABLgAECn8uAAIBAAkJfxyjEQBmAgABAAkJfxyjEQBmAgAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgAECgYJCAAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8UAAISAAMJyiA8IQATAQASAAMJyiA8IQATAQAuAAQKfywAAhIACQkvGgQPADcCABIACQkvGgQPADcCAAAA.Enoira:BAAALgAECgEJAgAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAABLgAECn8aAAILAAYJ8BUNGgBFAQALAAYJ8BUNGgBFAQAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Et='Ethel:BAAALgAECgEJAQAAAA==.',
Ev='Evillizard:BAABLgAECn8XAAIZAAgJ2wq7PgArAQAZAAgJ2wq7PgArAQAAAA==.',
Ex='Exhumer:BAABLgAECn8lAAIMAAgJuSUADgDzAgAMAAgJuSUADgDzAgAAAA==.',
Fa='Faffard:BAABLgAECn8cAAIFAAYJrxEwgQA3AQAFAAYJrxEwgQA3AQABLgAECgkJOQAbAEUJAA==.Fame:BAAALgAFFAEJAQABLgAFFAYJGAAZAPkXAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgQJBAAAAA==.',
Fe='Fearbilly:BAAALgAECgUJCAAAAA==.Felbilly:BAAALgAECgEJAQAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAABLgAECn8cAAMWAAYJ1AJukwCKAAAWAAYJ1AJukwCKAAAcAAEJrAHCpwASAAAAAA==.',
Fl='Flap:BAACLgAFFH8YAAIZAAYJ+RdTHwBeAQAZAAYJ+RdTHwBeAQAuAAQKfxsAAxkACQl7G24cAOQBABkACQl7G24cAOQBABcAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fu='Furbalkanaka:BAAALgADCgEJAQAAAA==.',
Fy='Fystie:BAABLgAECn8mAAMWAAYJyBmRNgC8AQAWAAYJyBmRNgC8AQAcAAUJXw5RUADHAAABLgAECgkJOQAbAEUJAA==.',
Ga='Galacticfox:BAAALgAECgIJAgAAAA==.Galpally:BAABLgAECn8kAAIMAAcJ5xOEfgBvAQAMAAcJ5xOEfgBvAQAAAA==.Ganzar:BAAALgADCgMJBAABLgAFFAMJEwADAMMkAA==.Garin:BAAALgAECgUJBgAAAA==.',
Ge='Genma:BAAALgAECgQJBAAAAA==.Gennic:BAAALgADCgcJBwAAAA==.Gettinskins:BAAALgAECgMJAwAAAA==.',
Gi='Gishongar:BAAALgAECgkJCgAAAA==.',
Gl='Glorak:BAABLgAECn8nAAIFAAcJdghOiAApAQAFAAcJdghOiAApAQAAAA==.',
Gr='Grashen:BAABLgAECn8mAAIJAAcJARtkKAAYAgAJAAcJARtkKAAYAgAAAA==.Gravorik:BAABLgAFFH8GAAMLAAMJPAfvEABzAAALAAMJXgXvEABzAAAMAAEJbwfKswBDAAAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDwAAAA==.',
Gs='Gsm:BAABLgAECn85AAINAAkJRRrBDgCAAgANAAkJRRrBDgCAAgAAAA==.',
Gu='Gulritz:BAAALgAECgIJAgAAAA==.Gulrum:BAAALgADCgEJAQAAAA==.Gurlyman:BAAALgAECgUJDAAAAA==.',
Ha='Haikara:BAAALgADCgMJAwAAAA==.Hante:BAAALgADCgcJEAAAAA==.Hartmonster:BAAALgAECgQJCAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMFAAcJIQVmbQAfAQAFAAYJ0gVmbQAfAQAaAAEJrwFeRQAbAAAAAA==.Hideous:BAAALgAECgQJCQAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgUJEgAAAA==.Hotspur:BAAALgAECgMJAwABLgAECggJKAAWAPQVAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ia='Iaanditos:BAAALgADCgYJBgAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilisselia:BAAALgADCgcJBwAAAA==.Ilokana:BAAALgAECgUJCgAAAA==.Ilostmybible:BAAALgAECgIJAgAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgYJEwAAAA==.',
It='Itzbarney:BAAALgAECggJEwAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacsknight:BAAALgAECgUJBwAAAA==.Jacspally:BAABLgAECn8iAAMMAAkJdRtzIACEAgAMAAkJdRtzIACEAgAdAAEJ0AMQnAAiAAAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8jAAIeAAkJkSD/AwDaAgAeAAkJkSD/AwDaAgAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAABLgAECn82AAMcAAkJ8xSMFgAXAgAcAAkJ8xSMFgAXAgAeAAEJAATIiAARAAAAAA==.Jellexy:BAABLgAECn8mAAICAAYJAQPKAQGlAAACAAYJAQPKAQGlAAAAAA==.',
Ji='Jimlahey:BAAALgAECgMJAwABLgAFFAUJGQACADEfAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8aAAIKAAUJlxasHgBrAQAKAAUJlxasHgBrAQAuAAQKfzIAAgoACQn5HOEQAJUCAAoACQn5HOEQAJUCAAAA.Jonnyfive:BAABLgAECn8UAAIMAAUJgw994wDWAAAMAAUJgw994wDWAAAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIFAAkJ6he1LgAdAgAFAAkJ6he1LgAdAgAAAA==.Kaisa:BAAALgADCgcJBwAAAA==.Kalimthor:BAAALgADCgEJAQAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAABLgAECn8eAAIMAAgJZBQmVQDIAQAMAAgJZBQmVQDIAQAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8sAAMFAAgJ8B5KBwA2AgAFAAcJnyNKBwA2AgAaAAYJEw3CCgBuAQAuAAQKf0EAAxoACQkiJo8CAIkDABoACQkYIo8CAIkDAAUACQkiJr4GACYDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgUJBQAAAA==.Keheo:BAAALgAECgQJCwAAAA==.',
Kh='Khandragho:BAAALgAECgYJBgAAAA==.Khaza:BAAALgAECgUJBQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kiri:BAAALgAECgMJBAABLgAECgkJMAAfAEMRAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn9PAAIEAAkJGSJ+AQAgAwAEAAkJGSJ+AQAgAwAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIdAAkJbRfBJgD0AQAdAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgUJDgAAAA==.Kruger:BAABLgAECn8jAAIIAAcJ+geGnwAAAQAIAAcJ+geGnwAAAQAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.Krzykanaka:BAAALgADCgIJAwAAAA==.',
Kt='Ktanna:BAABLgAECn8XAAIgAAcJaAiGNADoAAAgAAcJaAiGNADoAAAAAA==.',
Ku='Kublakhan:BAAALgAECgkJEAAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAYJKgALALwbAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8gAAIJAAkJixxDKQAUAgAJAAkJixxDKQAUAgAAAA==.Lapras:BAEBLgAFFH8NAAIZAAUJeyZAFQC7AQAZAAUJeyZAFQC7AQAAAA==.Lateralus:BAABLgAECn8uAAIMAAkJvhn8JwBhAgAMAAkJvhn8JwBhAgAAAA==.Laureli:BAABLgAECn8gAAIBAAYJbwOlcgCcAAABAAYJbwOlcgCcAAAAAA==.',
Le='Leeta:BAABLgAECn8oAAIeAAgJkx2lCQBLAgAeAAgJkx2lCQBLAgAAAA==.Legendx:BAAALgADCgUJBwAAAA==.Letholdus:BAABLgAECn8TAAIEAAkJKw4WDACzAQAEAAkJKw4WDACzAQAAAA==.',
Li='Lightningg:BAABLgAECn8fAAIXAAkJAAyRCQCLAQAXAAkJAAyRCQCLAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgABLgAFFAQJDgACAOwYAA==.',
Lo='Loahavemercy:BAAALgAECgEJAQAAAA==.Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgAECgUJEgAAAA==.Losoz:BAAALgAECgEJAgAAAA==.',
Lu='Lucariel:BAABLgAECn8hAAIDAAkJjRyaFwC3AgADAAkJjRyaFwC3AgAAAA==.Lusilsandrus:BAAALgAECgYJEwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAABLgAFFH8HAAIJAAMJEA5iUACtAAAJAAMJEA5iUACtAAAAAA==.Magusbilly:BAAALgAECgQJBAAAAA==.Mahoutsukai:BAABLgAECn8gAAICAAkJKQOuqwAlAQACAAkJKQOuqwAlAQAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8oAAINAAgJXQhcSAAOAQANAAgJXQhcSAAOAQAAAA==.',
Me='Mechaknight:BAAALgAECgUJCgAAAA==.',
Mi='Mildrik:BAABLgAECn8fAAIBAAkJCQpSMACLAQABAAkJCQpSMACLAQAAAA==.Miracledh:BAABLgAECn8aAAIgAAgJkiUmBgDUAgAgAAgJkiUmBgDUAgAAAA==.Mirkdrak:BAABLgAECn8iAAMZAAYJugtSUQDlAAAZAAYJugtSUQDlAAAXAAMJyQJmNgBjAAAAAA==.Misheard:BAACLgAFFH8DAAIVAAIJmBGYlQBCAAAVAAIJmBGYlQBCAAAuAAQKfzoAAhUACQnKIKEUAJsCABUACQnKIKEUAJsCAAAA.Misjudged:BAABLgAECn8XAAQZAAgJbxG9LgB8AQAZAAgJbxG9LgB8AQAXAAQJhw0dKQDWAAAYAAIJghghOwA0AAAAAA==.Missus:BAAALgAFFAMJAwAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgQJBQAAAA==.Mizzen:BAABLgAECn8qAAMhAAkJ/R+JBgDgAgAhAAkJ/R+JBgDgAgAiAAEJawSMpQAdAAABLgAFFAcJGAAQADEUAA==.',
Mo='Mohtavius:BAABLgAECn81AAITAAkJlhkNCgBOAgATAAkJlhkNCgBOAgAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn85AAIbAAkJRQlAEQAuAQAbAAkJRQlAEQAuAQAAAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Mu='Mulnier:BAAALgADCgkJCgAAAA==.Munkìe:BAAALgAECgUJDQABLgAECgkJOQANAEUaAA==.Muura:BAABLgAECn8hAAIDAAkJEA2HpQAhAQADAAkJEA2HpQAhAQAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJEgAAAA==.',
Na='Nakavelli:BAAALgAECgEJAQAAAA==.Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8tAAIJAAkJZR00DgDfAgAJAAkJZR00DgDfAgAAAA==.Nattal:BAAALgADCgUJBQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJDAAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAgJKgAYAOIdAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Ot='Otwin:BAABLgAECn8YAAMJAAUJCBmKVQBbAQAJAAUJCBmKVQBbAQANAAEJnAceswAlAAAAAA==.',
Pa='Pahuum:BAAALgAECgUJEQAAAA==.Paimon:BAABLgAECn8ZAAILAAgJJxxWCgAiAgALAAgJJxxWCgAiAgABLgAFFAYJGAAZAPkXAA==.Paintrainn:BAABLgAECn8XAAIJAAgJdgEFmwCVAAAJAAgJdgEFmwCVAAAAAA==.Palewhiteman:BAABLgAECn8hAAIdAAgJ5hkzGwAoAgAdAAgJ5hkzGwAoAgAAAA==.Palleigh:BAABLgAECn8lAAIdAAkJbg+uIwDlAQAdAAkJbg+uIwDlAQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8oAAIWAAgJ9BWdLADzAQAWAAgJ9BWdLADzAQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8kAAIFAAkJTxmDJwA9AgAFAAkJTxmDJwA9AgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Pl='Plague:BAAALgAFFAIJAgABLgAFFAMJEwADAMMkAA==.',
Po='Poondor:BAABLgAECn8YAAIdAAgJ0hMwJQDbAQAdAAgJ0hMwJQDbAQAAAA==.',
Pr='Predaturd:BAAALgAECggJBQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Qi='Qindere:BAABLgAECn8VAAICAAcJmQMA/gD/AAACAAcJmQMA/gD/AAAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn9EAAIFAAkJPhq/IgBVAgAFAAkJPhq/IgBVAgAAAA==.Rakshaman:BAAALgAECgcJEgAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgYJCwABLgAFFAMJEwADAMMkAA==.',
Re='Reihino:BAAALgAECgYJCQAAAA==.Resbak:BAABLgAECn8ZAAIcAAgJ3w5TLQBrAQAcAAgJ3w5TLQBrAQAAAA==.Resiaus:BAABLgAECn89AAIYAAkJyRyIBADgAgAYAAkJyRyIBADgAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECgcJDwAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Robinho:BAAALgAECgcJDQAAAA==.Rocketabu:BAAALgAECgMJBwAAAA==.Roctheist:BAABLgAECn8UAAMQAAYJEAbHSAC8AAAQAAYJEAbHSAC8AAAHAAYJEwZNTgCjAAAAAA==.Rocthoeb:BAABLgAECn80AAITAAkJxRH/EQDoAQATAAkJxRH/EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAABLgAECn8qAAMjAAkJOSPeAQAWAwAjAAkJOSPeAQAWAwAWAAEJ8AT+9wAaAAAAAA==.',
Sa='Saeris:BAAALgAECgUJBwAAAA==.Saintalpha:BAEALgAECgEJAQABLgAECggJFQAfAJkTAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFQAfAJkTAA==.Saintkhal:BAEALgAECgQJDQABLgAECggJFQAfAJkTAA==.Saintmedicus:BAEBLgAECn8VAAMfAAgJmROPNwA0AQAfAAUJZBePNwA0AQAQAAMJ0w0SYACUAAAAAA==.Saintshammy:BAABLgAFFH8FAAIJAAMJWxWjSADFAAAJAAMJWxWjSADFAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Saki:BAAALgADCgUJBQAAAA==.Sanctor:BAABLgAECn8dAAIdAAcJeyJ0EgB/AgAdAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Sangairee:BAAALgAECgEJAQAAAA==.Saraya:BAABLgAECn8WAAIdAAgJxBdEHgAOAgAdAAgJxBdEHgAOAgAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8jAAIfAAkJYh1eCADuAgAfAAkJYh1eCADuAgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shanoodles:BAAALgAECgUJCQAAAA==.Shibaryotaro:BAAALgAECgEJAQAAAA==.Shiftee:BAAALgAECgQJBAABLgAECgcJHAAFABsWAA==.Shinstabber:BAABLgAECn8jAAIUAAkJARRiEwDZAQAUAAkJARRiEwDZAQAAAA==.Shivantice:BAAALgADCgUJBQAAAA==.Shivantis:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Shruggie:BAABLgAECn8uAAMgAAgJVxZ/FQDdAQAgAAgJVxZ/FQDdAQAVAAQJDAN8+QBOAAAAAA==.',
Si='Silven:BAAALgAECgYJDgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8aAAIKAAkJpxmGEgCEAgAKAAkJpxmGEgCEAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8cAAIFAAcJGxZxLwD0AQAFAAcJGxZxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgAECgYJCQAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8tAAMaAAkJuwdaEwAmAQAkAAgJKARHLQA7AQAaAAkJnAdaEwAmAQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAJADYRAA==.Starlie:BAAALgAECgUJDgAAAA==.Stormstrike:BAAALgAECgcJBgAAAA==.Stratacaster:BAABLgAECn8YAAIIAAcJ0QIx1ACsAAAIAAcJ0QIx1ACsAAAAAA==.Strawberry:BAAALgAECgYJEAAAAA==.Stuckinwell:BAACLgAFFH8FAAMIAAIJkBjuNQCnAAAIAAIJGBDuNQCnAAAbAAEJlBa5IwBNAAAuAAQKfxsAAwgACQn6GsEzAD0CAAgACAnpFsEzAD0CABsABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAIWAAIJhh6QFQC3AAAWAAIJhh6QFQC3AAABLgAFFAgJKgAYAOIdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDwAAAA==.Synfyl:BAAALgAECgUJBQAAAA==.Synpathi:BAEALgADCgEJAQABLgAECgcJVAAlANITAA==.Synsyn:BAEBLgAECn9UAAMlAAcJ0hNMDQCCAQAlAAcJ0hNMDQCCAQAIAAYJ0AmprwDkAAAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8fAAICAAkJcg/1hgBmAQACAAkJcg/1hgBmAQAAAA==.',
Te='Teanfists:BAAALgAECgYJCgAAAA==.Temna:BAABLgAECn85AAIMAAkJBiS2BQBEAwAMAAkJBiS2BQBEAwAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAABLgAECn8gAAIFAAYJgBzCTwCuAQAFAAYJgBzCTwCuAQAAAA==.Thespaniard:BAABLgAECn8fAAIQAAkJqxhdFAArAgAQAAkJqxhdFAArAgAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAABLgAECn8WAAIeAAgJlQlFLwDpAAAeAAgJlQlFLwDpAAAAAA==.Tinbasher:BAAALgAECgUJCwAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAABLgAECn8eAAMWAAkJ7gn1SABoAQAWAAkJ7gn1SABoAQAcAAEJ5Qy1iwAyAAAAAA==.Tricky:BAAALgAECgUJDwAAAA==.Triviousox:BAABLgAECn8XAAIMAAcJkw+PkwBJAQAMAAcJkw+PkwBJAQAAAA==.Tryxx:BAAALgADCgUJBQAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAFFAUJEAAmAMYdAA==.Twotvmage:BAABLgAECn8uAAMCAAkJJB3oKAB0AgACAAkJJB3oKAB0AgAmAAEJIA2UFwAuAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Uneedarez:BAAALgAECgQJBAAAAA==.Unglued:BAAALgAECgYJBgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJDQABLgAECgkJNwAIAA8cAA==.',
Up='Uplift:BAABLgAFFH8FAAIhAAQJXRiCEQArAQAhAAQJXRiCEQArAQABLgAFFAgJHgACAJsbAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Ut='Uttrsdeek:BAAALgAFFAIJAgAAAA==.',
Va='Vale:BAAALgAECggJCAAAAA==.Valkky:BAABLgAECn82AAMnAAkJXRbSBwD8AQAnAAkJsxXSBwD8AQAVAAQJOA0VowDOAAAAAA==.Valky:BAAALgAECgEJAQABLgAECgkJNgAnAF0WAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn8wAAQfAAkJQxHTHQDdAQAfAAkJvQ3THQDdAQAHAAcJiw9gNQAoAQAQAAIJ2wREegBFAAAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vanity:BAAALgAECgUJBQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECggJEAABLgAECgkJMAAfAEMRAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn85AAIFAAkJbx5cEADKAgAFAAkJbx5cEADKAgAAAA==.Vessna:BAABLgAECn8iAAICAAYJIAfK2wDdAAACAAYJIAfK2wDdAAABLgAECgYJIgAZALoLAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAABLgAECn8gAAIjAAcJ1iJwBwBgAgAjAAcJ1iJwBwBgAgAAAA==.',
Vm='Vmro:BAAALgADCgYJFgAAAA==.',
Vo='Voras:BAAALgAECgYJEQAAAA==.Vorttex:BAAALgAECgUJEQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHQAZAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8oAAInAAgJvRomBwARAgAnAAgJvRomBwARAgAAAA==.',
Wh='Whiskeyrick:BAAALgAECgQJBAAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAwAAAA==.Winters:BAAALgAECgEJAQAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIQAAgJ4RsHEQB4AgAQAAgJ4RsHEQB4AgAAAA==.',
Xi='Xivago:BAAALgAECgUJCQAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAACLgAFFH8HAAIkAAMJcQgoIgDBAAAkAAMJcQgoIgDBAAAuAAQKfxYAAyQACAkDDnskAHoBACQACAkDDnskAHoBABoABAmABINqAJQAAAAA.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yo='Yoshino:BAAALgAECgUJBgABLgAECgYJGgACANMHAA==.',
Yu='Yuzuriha:BAAALgAECgYJDwAAAA==.',
Za='Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgAECgcJCwAAAA==.',
Zo='Zophier:BAAALgAECgQJBQAAAA==.Zouk:BAAALgAECgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAABLgAECn8YAAIaAAcJhwxrFQALAQAaAAcJhwxrFQALAQAAAA==.',
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
