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

local lookup = {'Warrior-Fury','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Warrior-Protection','Rogue-Subtlety','DeathKnight-Blood','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Destruction','Druid-Balance','Shaman-Elemental','Druid-Guardian','Priest-Holy','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Druid-Feral','Hunter-Survival','Warlock-Affliction','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ab='Abugarcia:BAAALgADCgYJCgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAABLgAECn8VAAIBAAcJYxBAQgAkAQABAAcJYxBAQgAkAQAAAA==.Akusenshi:BAABLgAECn8UAAIBAAcJOxA0NABkAQABAAcJOxA0NABkAQAAAA==.',
Al='Alarr:BAAALgAECgYJBwABLgAFFAMJCQACAPcYAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAABLgAECn8YAAMDAAYJQBU+jgA0AQADAAYJQBU+jgA0AQAEAAEJxxB7MQAvAAAAAA==.Alexi:BAAALgADCgkJCwAAAA==.Alivis:BAEALgAECgQJBAABLgAECgkJLgAFAGkgAA==.Alzith:BAAALgAECgQJBQABLgAECggJEQAGAAAAAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAkJNQAHAE0lAA==.',
Ap='Apexalpha:BAAALgAECgQJCAAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgAECgcJCgAAAA==.Arold:BAABLgAECn8lAAIIAAkJRhZmLAAbAgAIAAkJRhZmLAAbAgAAAA==.',
As='Asylia:BAACLgAFFH8KAAIJAAQJNhGCCQA5AQAJAAQJNhGCCQA5AQAuAAQKfxcAAgkACAlLGy4hABcCAAkACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8aAAIKAAYJVw1uTwD6AAAKAAYJVw1uTwD6AAAAAA==.',
Au='Aurelliae:BAABLgAECn8WAAIFAAgJtBU1SACxAQAFAAgJtBU1SACxAQAAAA==.',
Av='Avesiren:BAABLgAECn8hAAILAAcJLhJ9FwBIAQALAAcJLhJ9FwBIAQAAAA==.',
Ax='Axxion:BAAALgADCgYJBgAAAA==.',
Ay='Ayidá:BAAALgAECgcJDwAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECgcJDAAAAA==.Babymamaa:BAAALgAECgQJCQAAAA==.Babymuffins:BAABLgAECn8fAAIMAAYJ2iGMTQDGAQAMAAYJ2iGMTQDGAQAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAAALgAECgYJCwAAAA==.Beklee:BAAALgADCgUJBQAAAA==.Belanda:BAAALgAECgMJBQAAAA==.Belgord:BAAALgAECgYJEwAAAA==.Belin:BAAALgADCgkJFgAAAA==.Belmond:BAAALgAECgQJCAAAAA==.',
Bl='Blackmill:BAAALgAECgYJDAAAAA==.Blayrog:BAABLgAECn8pAAICAAgJuBR8ZACbAQACAAgJuBR8ZACbAQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8vAAMNAAkJGBjdCwASAgANAAkJzRfdCwASAgABAAYJ/RDSUQBiAQABLgAFFAYJFwAOALEUAA==.Bobbyknocker:BAAALgAECgcJBwAAAA==.Bolf:BAAALgAECgYJEwAAAA==.Boombaaby:BAABLgAECn8eAAIFAAgJcgspXQB1AQAFAAgJcgspXQB1AQAAAA==.Bootzee:BAABLgAECn8gAAIJAAcJbxtxIwAfAgAJAAcJbxtxIwAfAgAAAA==.',
Br='Brewglaive:BAAALgAECgEJAgAAAA==.Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAABLgAECn8bAAIOAAgJLAmXMwApAQAOAAgJLAmXMwApAQAAAA==.Brunhilian:BAAALgAECgUJCQAAAA==.',
Bu='Buckmaster:BAAALgAECgMJAwAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAABLgAECn8fAAIBAAYJMwcZWADVAAABAAYJMwcZWADVAAAAAA==.Calada:BAAALgAECgYJDAAAAA==.Callypso:BAAALgAECgYJBgABLgAECgYJGgAKAFcNAA==.Carbion:BAAALgADCgkJCQAAAA==.',
Ce='Cedarnia:BAAALgADCggJBwAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAQAGAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8eAAIJAAkJOxaxGwBTAgAJAAkJOxaxGwBTAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJDgAAAA==.',
Co='Corrynn:BAAALgAECgcJEgAAAA==.',
Cr='Cribbage:BAACLgAFFH8IAAIPAAMJwB4XEgD8AAAPAAMJwB4XEgD8AAAuAAQKfycAAw8ACAljImkIAGACAA8ACAljImkIAGACAA0AAQnMGsZeAEcAAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgADCggJDwAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgUJEwAAAA==.',
Cy='Cynosure:BAABLgAECn8xAAIQAAkJvRmpDgAoAgAQAAkJvRmpDgAoAgAAAA==.Cytronsneak:BAAALgAECgQJCAAAAA==.',
Da='Dabb:BAAALgADCggJDgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgUJDQAAAA==.Daliå:BAAALgAECgEJAQAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8eAAIIAAgJQgtkaQBeAQAIAAgJQgtkaQBeAQAAAA==.Darkheaven:BAABLgAECn8bAAIMAAgJegj+kwAwAQAMAAgJegj+kwAwAQAAAA==.Darkkanaka:BAAALgADCgEJAQAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAABLgAECn8YAAIRAAgJnwKoNQCnAAARAAgJnwKoNQCnAAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8YAAISAAYJXxgzHQCSAQASAAYJXxgzHQCSAQAuAAQKfykAAhIACAmMIocbAFsCABIACAmMIocbAFsCAAEuAAQKBQkKAAYAAAAA.Demonkanaka:BAAALgADCgIJAgAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgAECgUJBQAAAA==.Devinetoro:BAABLgAECn8lAAIMAAgJ9QdNmQAnAQAMAAgJ9QdNmQAnAQAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAITAAkJGRcmLAD/AQATAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn8rAAQUAAgJVxsVBAAsAgAUAAgJVxsVBAAsAgAVAAQJTRISKgCBAAAWAAMJLQYtaQB0AAAAAA==.',
Do='Doree:BAAALgADCgYJBgAAAA==.Dotdotoops:BAAALgAECgEJAQAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAUJEAAXALkKAA==.Dreadsofdeth:BAABLgAECn8VAAICAAYJixh1ngCZAQACAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJDwAAAA==.Drklhtkanaka:BAAALgADCgYJBgAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8sAAIIAAgJ2RCLVACTAQAIAAgJ2RCLVACTAQAAAA==.',
Ei='Einheri:BAABLgAECn8sAAIBAAgJ0xyJFwAeAgABAAgJ0xyJFwAeAgAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgAECgYJCAAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8PAAIQAAMJ/hwhHgAHAQAQAAMJ/hwhHgAHAQAuAAQKfywAAhAACQkvGvQMAEACABAACQkvGvQMAEACAAAA.Enoira:BAAALgAECgEJAgAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAAALgAECgYJDwAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Et='Ethel:BAAALgAECgEJAQAAAA==.',
Ev='Evillizard:BAABLgAECn8WAAIWAAcJJwrERwDoAAAWAAcJJwrERwDoAAAAAA==.',
Ex='Exhumer:BAABLgAECn8jAAIMAAgJciUfDADwAgAMAAgJciUfDADwAgAAAA==.',
Fa='Faffard:BAABLgAECn8WAAIFAAYJzgprkwD+AAAFAAYJzgprkwD+AAABLgAECgkJOAAYAAQJAA==.Fame:BAAALgAFFAEJAQABLgAFFAYJFwAWAPkXAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgEJAQAAAA==.',
Fe='Fearbilly:BAAALgAECgQJBwAAAA==.Felbilly:BAAALgADCgEJAQAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAAALgAECgYJEQAAAA==.',
Fl='Flap:BAACLgAFFH8XAAIWAAYJ+RdjFwBpAQAWAAYJ+RdjFwBpAQAuAAQKfxkAAxYACAlOGG4cAOQBABYACAlOGG4cAOQBABQAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fu='Furbalkanaka:BAAALgADCgEJAQAAAA==.',
Fy='Fystie:BAABLgAECn8bAAMTAAYJ3RgyNgCtAQATAAYJ3RgyNgCtAQAZAAUJwAc0WQCRAAABLgAECgkJOAAYAAQJAA==.',
Ga='Galpally:BAABLgAECn8gAAIMAAcJ4xPlcQBwAQAMAAcJ4xPlcQBwAQAAAA==.Ganzar:BAAALgADCgMJBAABLgAFFAMJDQADALckAA==.Garin:BAAALgAECgUJBgAAAA==.',
Ge='Genma:BAAALgAECgQJAwAAAA==.Gennic:BAAALgADCgcJBwAAAA==.Gettinskins:BAAALgADCgEJAQAAAA==.',
Gi='Gishongar:BAAALgAECgEJAQAAAA==.',
Gl='Glorak:BAABLgAECn8hAAIFAAcJJQaDiQASAQAFAAcJJQaDiQASAQAAAA==.',
Gr='Grashen:BAABLgAECn8eAAIJAAYJsh1dLADtAQAJAAYJsh1dLADtAQAAAA==.Gravorik:BAAALgAFFAEJAQAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDgAAAA==.',
Gs='Gsm:BAABLgAECn8uAAIaAAgJ4RtGEgBGAgAaAAgJ4RtGEgBGAgAAAA==.',
Gu='Gulritz:BAAALgAECgIJAgAAAA==.Gurlyman:BAAALgAECgQJBwAAAA==.',
Ha='Haikara:BAAALgADCgMJAwAAAA==.Hante:BAAALgADCgcJEAAAAA==.Hartmonster:BAAALgAECgQJCAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMFAAcJIQVmbQAfAQAFAAYJ0gVmbQAfAQAXAAEJrwF8PwAcAAAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgQJCAAAAA==.Hotspur:BAAALgAECgMJAwABLgAECgYJHwATAEsXAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ia='Iaanditos:BAAALgADCgYJBgAAAA==.',
Ig='Ignath:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilokana:BAAALgAECgMJBQAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgYJCwAAAA==.',
It='Itzbarney:BAAALgAECggJEQAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacspally:BAABLgAECn8aAAIMAAgJChqsMwAZAgAMAAgJChqsMwAZAgAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8gAAIbAAgJISHOBQCKAgAbAAgJISHOBQCKAgAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAABLgAECn8sAAIZAAgJ+xM3HgC8AQAZAAgJ+xM3HgC8AQAAAA==.Jellexy:BAABLgAECn8bAAICAAYJdgKj+gCOAAACAAYJdgKj+gCOAAAAAA==.',
Ji='Jimlahey:BAAALgAECgMJAwABLgAFFAUJGQACADEfAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8SAAIKAAQJNRWNIQANAQAKAAQJNRWNIQANAQAuAAQKfzAAAgoACAk1Hc0WAD4CAAoACAk1Hc0WAD4CAAAA.Jonnyfive:BAAALgAECgQJCgAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIFAAkJ6hc4JwAsAgAFAAkJ6hc4JwAsAgAAAA==.Kaisa:BAAALgADCgcJBwAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAABLgAECn8VAAIMAAYJ8hHzkQAzAQAMAAYJ8hHzkQAzAQAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8sAAMFAAgJ8B7xAgBKAgAFAAcJnyPxAgBKAgAXAAYJEw3CCgBuAQAuAAQKf0EAAxcACQkiJo8CAIkDABcACQkYIo8CAIkDAAUACQkiJvAEADIDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgUJBQAAAA==.Keheo:BAAALgAECgQJCwAAAA==.',
Kh='Khandragho:BAAALgAECgYJBgAAAA==.Khaza:BAAALgAECgUJBQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kiri:BAAALgAECgEJAQABLgAECggJJQAcABASAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn9PAAIEAAkJHSILAQAgAwAEAAkJHSILAQAgAwAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIdAAkJbRfBJgD0AQAdAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgQJCQAAAA==.Kruger:BAABLgAECn8jAAIIAAcJ+ge9kwAKAQAIAAcJ+ge9kwAKAQAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.Krzykanaka:BAAALgADCgIJAgAAAA==.',
Kt='Ktanna:BAABLgAECn8XAAIeAAcJaAh4LgDsAAAeAAcJaAh4LgDsAAAAAA==.',
Ku='Kublakhan:BAAALgAECggJDgAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAUJHwALAKYgAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8gAAIJAAkJixz2JAAXAgAJAAkJixz2JAAXAgAAAA==.Lapras:BAEBLgAFFH8IAAIWAAUJeyYQDwDGAQAWAAUJeyYQDwDGAQAAAA==.Lateralus:BAABLgAECn8kAAIMAAgJOxSOVgCvAQAMAAgJOxSOVgCvAQAAAA==.Laureli:BAABLgAECn8VAAIBAAYJxgIgbQCOAAABAAYJxgIgbQCOAAAAAA==.',
Le='Leeta:BAABLgAECn8fAAIbAAYJ2Ry5EwCYAQAbAAYJ2Ry5EwCYAQAAAA==.Legendx:BAAALgADCgUJBwAAAA==.Letholdus:BAAALgAECggJCAAAAA==.',
Li='Lightningg:BAABLgAECn8cAAIUAAgJmAxKCgBnAQAUAAgJmAxKCgBnAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgABLgAFFAMJCQACAPcYAA==.',
Lo='Loahavemercy:BAAALgAECgEJAQAAAA==.Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgAECgQJCQAAAA==.Losoz:BAAALgAECgEJAgAAAA==.',
Lu='Lucariel:BAAALgAECggJEQAAAA==.Lusilsandrus:BAAALgAECgYJEwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAAALgAFFAIJAgAAAA==.Magusbilly:BAAALgADCgYJBgAAAA==.Mahoutsukai:BAABLgAECn8fAAICAAgJwwJMxwDfAAACAAgJwwJMxwDfAAAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8fAAIaAAYJnAjKVwDBAAAaAAYJnAjKVwDBAAAAAA==.',
Me='Mechaknight:BAAALgAECgUJCAAAAA==.',
Mi='Mildrik:BAABLgAECn8cAAIBAAgJYQnsOABNAQABAAgJYQnsOABNAQAAAA==.Miracledh:BAABLgAECn8aAAIeAAgJkiXaBADeAgAeAAgJkiXaBADeAgAAAA==.Mirkdrak:BAABLgAECn8XAAMWAAYJ5gd6WQCnAAAWAAYJ5gd6WQCnAAAUAAMJyQJmNgBjAAAAAA==.Misheard:BAACLgAFFH8DAAISAAIJmBE/hABFAAASAAIJmBE/hABFAAAuAAQKfzYAAhIACQl6Hy8WAH8CABIACQl6Hy8WAH8CAAAA.Misjudged:BAABLgAECn8UAAQWAAcJqhCBOwAcAQAWAAcJqhCBOwAcAQAUAAQJhw0dKQDWAAAVAAIJghjiQgBWAAAAAA==.Missus:BAAALgAFFAMJAwAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgQJBQAAAA==.Mizzen:BAABLgAECn8oAAMfAAgJySHZCACkAgAfAAgJySHZCACkAgAgAAEJawTsmwAdAAABLgAFFAYJFwAOALEUAA==.',
Mo='Mohtavius:BAABLgAECn8rAAIPAAgJ6RYAEgC0AQAPAAgJ6RYAEgC0AQAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn84AAIYAAkJBAlSDwAwAQAYAAkJBAlSDwAwAQAAAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Mu='Mulnier:BAAALgADCgkJCgAAAA==.Munkìe:BAAALgAECgUJDQABLgAECggJLgAaAOEbAA==.Muura:BAABLgAECn8fAAIDAAkJcAtQogATAQADAAkJcAtQogATAQAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJEgAAAA==.',
Na='Nakavelli:BAAALgAECgEJAQAAAA==.Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8sAAIJAAgJ7xzAFQCDAgAJAAgJ7xzAFQCDAgAAAA==.Nattal:BAAALgADCgUJBQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJCwAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAgJIwAVAMQdAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Ot='Otwin:BAAALgAECgQJDgAAAA==.',
Pa='Pahuum:BAAALgAECgQJCQAAAA==.Paimon:BAABLgAECn8XAAILAAcJcRweDQDYAQALAAcJcRweDQDYAQABLgAFFAYJFwAWAPkXAA==.Paintrainn:BAABLgAECn8XAAIJAAgJdgHhjQCWAAAJAAgJdgHhjQCWAAAAAA==.Palewhiteman:BAABLgAECn8hAAIdAAgJ5hmJGAAsAgAdAAgJ5hmJGAAsAgAAAA==.Palleigh:BAABLgAECn8ZAAIdAAgJGQzbMQB5AQAdAAgJGQzbMQB5AQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8fAAITAAYJSxcVPgCIAQATAAYJSxcVPgCIAQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8hAAIFAAgJ0xlIMQAAAgAFAAgJ0xlIMQAAAgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Po='Poondor:BAABLgAECn8WAAIdAAgJZhOGIwDUAQAdAAgJZhOGIwDUAQAAAA==.',
Pr='Predaturd:BAAALgAECggJBQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Qi='Qindere:BAAALgAECgcJEwAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn9EAAIFAAkJPho/HQBhAgAFAAkJPho/HQBhAgAAAA==.Rakshaman:BAAALgAECgUJCgAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgYJCAABLgAFFAMJDQADALckAA==.',
Re='Reihino:BAAALgAECgUJBQAAAA==.Resbak:BAAALgAECggJDwAAAA==.Resiaus:BAABLgAECn89AAIVAAkJyRwlBADhAgAVAAkJyRwlBADhAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECgYJCwAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Robinho:BAAALgAECgcJDQAAAA==.Rocketabu:BAAALgAECgMJBAAAAA==.Roctheist:BAABLgAECn8UAAMOAAYJEAbHSAC8AAAOAAYJEAbHSAC8AAAcAAYJEwaZSACqAAAAAA==.Rocthoeb:BAABLgAECn80AAIPAAkJxRH/EQDoAQAPAAkJxRH/EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAABLgAECn8qAAMhAAkJOSNrAQAfAwAhAAkJOSNrAQAfAwATAAEJ8AQw6gAaAAAAAA==.',
Sa='Saeris:BAAALgAECgMJAwAAAA==.Saintalpha:BAEALgAECgEJAQABLgAECggJFAAHAJkTAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFAAHAJkTAA==.Saintkhal:BAEALgAECgQJCgABLgAECggJFAAHAJkTAA==.Saintmedicus:BAEBLgAECn8UAAMHAAgJmRNyMQAxAQAHAAUJZBdyMQAxAQAOAAMJ0w2TUwCZAAAAAA==.Saintshammy:BAABLgAFFH8FAAIJAAMJWxWCOwDaAAAJAAMJWxWCOwDaAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Saki:BAAALgADCgUJBQAAAA==.Sanctor:BAABLgAECn8dAAIdAAcJeyJ0EgB/AgAdAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Saraya:BAABLgAECn8VAAIdAAgJxBd6GwASAgAdAAgJxBd6GwASAgAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8gAAIHAAgJjh2dCwCXAgAHAAgJjh2dCwCXAgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shibaryotaro:BAAALgAECgEJAQAAAA==.Shiftee:BAAALgAECgQJBAABLgAECgcJHAAFABsWAA==.Shinstabber:BAABLgAECn8gAAIRAAgJ+hRTFQCnAQARAAgJ+hRTFQCnAQAAAA==.Shivantis:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwAGAAAAAA==.Shruggie:BAABLgAECn8iAAMeAAcJJRO0HQBpAQAeAAcJJRO0HQBpAQASAAIJJwS3CgElAAAAAA==.',
Si='Silven:BAAALgAECgYJDgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8YAAIKAAgJSxuWFABUAgAKAAgJSxuWFABUAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8cAAIFAAcJGxZxLwD0AQAFAAcJGxZxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgAECgYJCQAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8tAAMXAAkJuwcFEQA0AQAiAAgJKATiKQBCAQAXAAkJnAcFEQA0AQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAJADYRAA==.Starlie:BAAALgAECgUJDgAAAA==.Stormstrike:BAAALgAECgcJBgAAAA==.Stratacaster:BAABLgAECn8VAAIIAAYJAAPq0QCfAAAIAAYJAAPq0QCfAAAAAA==.Strawberry:BAAALgAECgUJDgAAAA==.Stuckinwell:BAACLgAFFH8FAAMIAAIJkBjuNQCnAAAIAAIJGBDuNQCnAAAYAAEJlBZmHwBNAAAuAAQKfxsAAwgACQn6GsEzAD0CAAgACAnpFsEzAD0CABgABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAITAAIJhh6QFQC3AAATAAIJhh6QFQC3AAABLgAFFAgJIwAVAMQdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDwAAAA==.Synpathi:BAEALgADCgEJAQABLgAECgYJTwAjAEQXAA==.Synsyn:BAEBLgAECn9PAAMjAAYJRBdYDABzAQAjAAYJRBdYDABzAQAIAAYJ0An5owDtAAAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8eAAICAAkJfQ1HiQC/AQACAAkJfQ1HiQC/AQAAAA==.',
Te='Teanfists:BAAALgAECgYJCgAAAA==.Temna:BAABLgAECn8uAAIMAAgJYyO4EADMAgAMAAgJYyO4EADMAgAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAABLgAECn8VAAIFAAYJIha8ZQBgAQAFAAYJIha8ZQBgAQAAAA==.Thespaniard:BAABLgAECn8dAAIOAAcJPhllJACHAQAOAAcJPhllJACHAQAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAABLgAECn8VAAIbAAgJggnCKADrAAAbAAgJggnCKADrAAAAAA==.Tinbasher:BAAALgAECgUJBwAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAABLgAECn8ZAAMTAAkJeAmNRABqAQATAAkJeAmNRABqAQAZAAEJ5QwVgAAyAAAAAA==.Tricky:BAAALgAECgQJCgAAAA==.Triviousox:BAABLgAECn8XAAIMAAcJkw81gwBOAQAMAAcJkw81gwBOAQAAAA==.Tryxx:BAAALgADCgUJBQAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAFFAUJDQAkAPkXAA==.Twotvmage:BAABLgAECn8uAAMCAAkJJB1bJAB1AgACAAkJJB1bJAB1AgAkAAEJIA30EwAxAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Unglued:BAAALgAECgYJBgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJDQABLgAECgkJNwAIAA8cAA==.',
Up='Uplift:BAABLgAFFH8FAAIfAAQJXRjdDQA7AQAfAAQJXRjdDQA7AQABLgAFFAgJGQACACEbAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Va='Vale:BAAALgAECggJCAAAAA==.Valkky:BAABLgAECn8sAAMlAAgJPxL9DABrAQAlAAgJUxH9DABrAQASAAQJOA0VowDOAAAAAA==.Valky:BAAALgADCgQJBAABLgAECggJLAAlAD8SAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn8lAAMcAAgJEBL2MAAxAQAcAAcJiw/2MAAxAQAHAAYJ+w2uMwAkAQAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECgcJCQABLgAECggJJQAcABASAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn8uAAIFAAgJtRuvLAATAgAFAAgJtRuvLAATAgAAAA==.Vessna:BAABLgAECn8XAAICAAYJOQQY6ACsAAACAAYJOQQY6ACsAAABLgAECgYJFwAWAOYHAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAABLgAECn8YAAIhAAcJTCDhBwA0AgAhAAcJTCDhBwA0AgAAAA==.',
Vm='Vmro:BAAALgADCgYJFgAAAA==.',
Vo='Voras:BAAALgAECgYJEQAAAA==.Vorttex:BAAALgAECgQJBwAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHAAWAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8fAAIlAAYJpRt9DAB0AQAlAAYJpRt9DAB0AQAAAA==.',
Wh='Whiskeyrick:BAAALgADCgMJAwAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAwAAAA==.Winters:BAAALgADCggJCAAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIOAAgJ4RsHEQB4AgAOAAgJ4RsHEQB4AgAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAACLgAFFH8HAAIiAAMJcQhqHQDRAAAiAAMJcQhqHQDRAAAuAAQKfxYAAyIACAkDDnshAIMBACIACAkDDnshAIMBABcABAmABINqAJQAAAAA.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yo='Yoshino:BAAALgAECgUJBQABLgAECgUJDgAGAAAAAA==.',
Yu='Yuzuriha:BAAALgAECgYJDwAAAA==.',
Za='Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgAECgEJAgAAAA==.',
Zo='Zophier:BAAALgAECgEJAQAAAA==.Zouk:BAAALgAECgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAABLgAECn8YAAIXAAcJhwwpEwAUAQAXAAcJhwwpEwAUAQAAAA==.',
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
