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

local lookup = {'Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Priest-Discipline','Priest-Shadow','Druid-Balance','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Monk-Brewmaster','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','Priest-Holy','Mage-Arcane','Druid-Guardian','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Mage-Fire','DeathKnight-Frost','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abelothh:BAABLgAECn8bAAMBAAkJOQxYYQB9AQABAAkJxwpYYQB9AQACAAQJOw34EwDwAAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIDAAcJyBqmMgAvAgADAAcJyBqmMgAvAgAAAA==.Aelita:BAABLgAECn8nAAMEAAcJXCDOAQCaAgAEAAcJXCDOAQCaAgAFAAIJ/BRrFgB5AAAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAABLgAECn8vAAMGAAkJ5BsoDgB4AgAGAAkJ5BsoDgB4AgAHAAUJxhOnaAD6AAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aidanpryde:BAAALgAECgQJCgAAAA==.Aimster:BAAALgAECgkJCAAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAACLgAFFH8OAAIIAAQJAyKfFACGAQAIAAQJAyKfFACGAQAuAAQKfx4AAwgACQnUHDAPAKQCAAgACQnUHDAPAKQCAAkABgl4DJPOAPUAAAAA.Akoni:BAAALgAECgYJEAABLgAECgkJJAAKAPEiAA==.',
Al='Allaris:BAABLgAECn8oAAIBAAkJUQh1dQBOAQABAAkJUQh1dQBOAQAAAA==.Allíesin:BAAALgAECgUJCAAAAA==.Almaperidia:BAAALgAECgQJBAAAAA==.Altryn:BAAALgAECgMJBgAAAA==.Alundrablaze:BAACLgAFFH8XAAILAAQJnRzeEQBBAQALAAQJnRzeEQBBAQAuAAQKfy0AAwsACQkJGF0bAHACAAsACQkJGF0bAHACAAwAAQmgEyknADoAAAAA.',
Am='Amarixa:BAAALgAECgMJAwABLgAECgkJDgANAAAAAA==.',
An='Anare:BAAALgAECgEJAQABLgAECggJCwANAAAAAA==.Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAIOAAQJyxmgIwAcAQAOAAQJyxmgIwAcAQAuAAQKfzgAAg4ACQlrITUHAMQCAA4ACQlrITUHAMQCAAAA.Anrraakk:BAAALgAECgQJBAAAAA==.Antsy:BAAALgAECgEJAgAAAA==.',
Ap='Apollis:BAAALgAECgMJBgAAAA==.',
Ar='Aram:BAAALgAECggJCgAAAA==.Aranthino:BAABLgAECn8oAAMPAAkJAhUGAwCGAQAPAAkJAhUGAwCGAQALAAUJbhCAEgABAQAAAA==.Arell:BAAALgAECgEJAQAAAA==.Armson:BAAALgAECgQJBAAAAA==.Arnzul:BAAALgAECgQJBAAAAA==.Aryabhatta:BAABLgAECn8tAAMQAAkJPx50GwCAAgAQAAkJPx50GwCAAgARAAYJ/BSNHwCgAQAAAA==.',
As='Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECggJCQAAAA==.',
At='Athellios:BAAALgAECgEJBAAAAA==.Athenarelia:BAABLgAECn8dAAILAAgJjBB6RwCQAQALAAgJjBB6RwCQAQAAAA==.',
Av='Avianae:BAAALgAECgIJAgABLgAECgQJBAANAAAAAA==.',
Ba='Backbush:BAAALgAECgQJBwAAAA==.Baelskrim:BAABLgAECn8WAAIMAAcJUR0pJQC/AQAMAAcJUR0pJQC/AQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAACLgAFFH8HAAISAAQJ2wfBPgDfAAASAAQJ2wfBPgDfAAAuAAQKf1sAAxIACQkAIsQDAJACABIACQnjIcQDAJACABMAAwlmD1kRAF8AAAAA.Baoshengdadi:BAAALgAECggJCAABLgAFFAQJFgALADsjAA==.Bashirr:BAAALgADCgIJAgAAAA==.',
Be='Beansfu:BAABLgAFFH8FAAMUAAIJdxKHLAB2AAAUAAIJdxKHLAB2AAAVAAEJRxFKHwA9AAABLgAFFAIJBwALAKMgAA==.Beansination:BAACLgAFFH8HAAMLAAIJoyA2WQCbAAALAAIJoyA2WQCbAAAMAAEJ5g7kVwA5AAAuAAQKfxYAAwwACQmtF+shANUBAAwACQmtF+shANUBAAsABQnIFPlRAD0BAAAA.Beefsupriem:BAABLgAECn8VAAIWAAkJ+RSeFgDSAQAWAAkJ+RSeFgDSAQAAAA==.Bellatrïx:BAAALgAECgEJAgABLgAECgUJCAANAAAAAA==.Belliaz:BAAALgAECgkJDgAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgAECgIJAgAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAFFAMJBgAIADkTAA==.',
Bl='Blackfuse:BAAALgAECggJEAAAAA==.Bloodlyfrost:BAABLgAECn8sAAIXAAkJCAYGiQBlAQAXAAkJCAYGiQBlAQAAAA==.Bloodmaji:BAAALgAECgUJBgAAAA==.Bloodwell:BAAALgAECgUJBQAAAA==.Bloodyguthix:BAAALgAECggJEgAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.Bovinar:BAAALgAECgYJBgAAAA==.Boyo:BAAALgADCgUJBQAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJEgABLgAFFAQJHAAFAAYXAA==.Breaknasweat:BAAALgAECgIJAgAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgAECgEJAQAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAUJDgASAOocAA==.',
Bu='Burningtaint:BAAALgAECgEJAgAAAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Calientay:BAABLgAECn8XAAIWAAkJQRIDBAC6AQAWAAkJQRIDBAC6AQABLgAFFAYJGAAQAC4XAA==.Candyquartz:BAAALgAECgEJAQAAAA==.Captaïn:BAAALgAECgkJCwAAAA==.Cathorn:BAAALgAECgEJAQAAAA==.Caylda:BAAALgAECgUJBQAAAA==.',
Ce='Celladorne:BAAALgAECgcJDgAAAA==.Centermass:BAAALgAECgMJBAAAAA==.',
Cg='Cg:BAAALgAECgYJBwAAAA==.',
Ch='Chibi:BAACLgAFFH8QAAIPAAQJ5gLiDgDSAAAPAAQJ5gLiDgDSAAAuAAQKfyoAAg8ACQnVEi8YAEcBAA8ACQnVEi8YAEcBAAAA.Chronokite:BAABLgAECn8bAAMYAAgJ8gikRAAXAQAYAAgJ8gikRAAXAQAZAAcJAgcWHwD+AAAAAA==.',
Cl='Clawburr:BAAALgADCgQJBAAAAA==.',
Co='Codebrown:BAAALgAECgEJAgAAAA==.Colair:BAAALgAECgQJBQAAAA==.Corpsegrin:BAAALgAECgMJAwAAAA==.',
Cp='Cpr:BAAALgAECgQJDgAAAA==.',
Cr='Crushed:BAABLgAECn8bAAMaAAgJqRlgEwCwAQAaAAgJqRlgEwCwAQABAAIJUw2h/wBpAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMLAAcJvBJkRgBoAQALAAcJvBJkRgBoAQAMAAUJxwesZwCkAAABLgAECggJGwAYAPIIAA==.',
Da='Da:BAAALgAECgEJAgAAAA==.Daldenn:BAAALgADCgkJCwAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8/AAIIAAkJhhrsDwCbAgAIAAkJhhrsDwCbAgAAAA==.Darkfuse:BAAALgAECgMJBAAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgAECgYJBAABLgAFFAQJEAARALgbAA==.Dayman:BAABLgAECn8YAAIJAAYJKRwOcACOAQAJAAYJKRwOcACOAQAAAA==.',
Db='Dbk:BAAALgAECgYJEgAAAA==.',
Dd='Ddraiggoch:BAAALgAECgUJBwABLgAECgkJJAAKAPEiAA==.',
De='Deader:BAABLgAECn8dAAMbAAkJfx3ODgB7AgAbAAkJfx3ODgB7AgAFAAMJOhOTagB0AAAAAA==.Deadlyydot:BAABLgAECn88AAIFAAcJZg+dCgALAQAFAAcJZg+dCgALAQAAAA==.Deadlyykiss:BAABLgAECn85AAIcAAYJqhDAAwADAQAcAAYJqhDAAwADAQAAAA==.Deanbaba:BAAALgADCgEJAQAAAA==.Deathelyn:BAAALgAECgEJAQAAAA==.Deathhowl:BAABLgAECn8aAAITAAkJTwriCQDEAAATAAkJTwriCQDEAAAAAA==.Deathstorm:BAAALgAECgEJAQAAAA==.Demonsaber:BAABLgAECn8nAAIDAAcJwgT3uwC0AAADAAcJwgT3uwC0AAAAAA==.Demonseed:BAAALgAECggJEgAAAA==.Demonslice:BAABLgAECn8lAAMWAAkJBw8mJQBPAQAWAAkJBw8mJQBPAQADAAQJ2wRs4QB0AAAAAA==.Dengfeijien:BAAALgAECgUJBwABLgAECgkJDgANAAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.Desended:BAAALgAECgUJBgAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgYJDQAAAA==.Dirtydotz:BAAALgAECgEJAQAAAA==.Dirë:BAAALgAECgEJAgABLgAECgYJDQANAAAAAA==.Disengage:BAACLgAFFH8KAAIQAAMJuAaaPQCzAAAQAAMJuAaaPQCzAAAuAAQKfzcAAhAACAnWFzlZAJkBABAACAnWFzlZAJkBAAAA.Displace:BAABLgAECn8iAAISAAkJmBFODgBGAQASAAkJmBFODgBGAQAAAA==.Divinewords:BAAALgAECgkJEAAAAA==.Divish:BAABLgAECn8qAAMZAAkJMRz2BgCPAgAZAAkJMRz2BgCPAgAYAAEJAABJqgAAAAAAAA==.',
Do='Dogan:BAAALgAECgQJBwAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgAECgEJAQAAAA==.Dotaldtrump:BAAALgAECgIJAgAAAA==.',
Dr='Dragkin:BAAALgADCgYJBgAAAA==.Dragonbourne:BAAALgADCgUJBQAAAA==.Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Dreyvia:BAAALgADCgUJBQAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJDQAAAA==.Dropdeath:BAAALgAECgUJBQAAAA==.Druecc:BAACLgAFFH8GAAIXAAEJvxCdbABDAAAXAAEJvxCdbABDAAAuAAQKfywAAhcACQk9F2o1AEMCABcACQk9F2o1AEMCAAAA.Druidlord:BAABLgAECn9WAAIdAAkJdAaICQDnAAAdAAkJdAaICQDnAAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECggJCQAAAA==.Duckyfur:BAAALgAECgIJAwAAAA==.Dumplíng:BAAALgAECgQJBAABLgAECgkJLwAGAOQbAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgYJDQANAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAgAAAA==.',
['Då']='Dågon:BAAALgAECgQJCAAAAA==.',
Ed='Edgerallen:BAACLgAFFH8GAAIOAAMJ+w1KOQDBAAAOAAMJ+w1KOQDBAAAuAAQKfx0AAw4ACQn6D+4iAJIBAA4ACQn6D+4iAJIBABUABgmuAv9hAIcAAAAA.',
Ei='Eitherwind:BAAALgAECgYJDAAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJGwAYAPIIAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAABLgAECn8VAAIHAAkJ4BEhLwDnAQAHAAkJ4BEhLwDnAQAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.Ellennia:BAABLgAECn8VAAIQAAUJzBt2HQDpAAAQAAUJzBt2HQDpAAAAAA==.',
Em='Emish:BAAALgADCgkJCQAAAA==.',
Er='Era:BAABLgAECn8wAAIeAAkJwhwPGAAuAgAeAAkJwhwPGAAuAgAAAA==.',
Et='Ethena:BAAALgAECgQJBQAAAA==.',
Ev='Evosaber:BAAALgAECgIJAgAAAA==.',
Ex='Executions:BAABLgAECn8WAAMfAAUJQRX3CADaAAAgAAQJNhS/EQAJAQAfAAQJbRT3CADaAAAAAA==.',
Fa='Fairlady:BAAALgAECgEJAQAAAA==.Fanara:BAABLgAECn8dAAIGAAYJ0w5BRAD7AAAGAAYJ0w5BRAD7AAAAAA==.Fangtazia:BAAALgAECgEJAQAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAABLgAECn8aAAQLAAgJCB7BGACEAgALAAgJCB7BGACEAgAMAAEJggpRtQAmAAAPAAEJHQBvSgAEAAAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgQJBgABLgAECgEJAQANAAAAAA==.Felbládes:BAAALgAECgMJBwAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8kAAIVAAgJzReBHQDBAQAVAAgJzReBHQDBAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.Feñ:BAAALgAECgEJAQAAAA==.',
Fi='Finluzzertok:BAAALgADCgQJBAABLgAECgkJKgAXADcEAA==.Fitua:BAABLgAECn8gAAISAAkJjwu3fgCGAQASAAkJjwu3fgCGAQAAAA==.Fizzbann:BAAALgAECgcJEQABLgAECgkJJAAKAPEiAA==.',
Fk='Fkingbeast:BAAALgAFFAkJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAABLgAECn8dAAITAAkJzApYIQBHAQATAAkJzApYIQBHAQAAAA==.Fortytwö:BAAALgAECgMJAwAAAA==.Foutre:BAABLgAECn8rAAIGAAkJ6w2oJwCSAQAGAAkJ6w2oJwCSAQAAAA==.',
Fr='Froghugger:BAAALgAECgUJBQAAAA==.Fruntstabba:BAAALgAECgUJBgAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fungus:BAACLgAFFH8NAAMGAAYJBR0AGQBSAQAGAAUJQh4AGQBSAQAdAAEJDhh3KAA8AAAuAAQKfy0AAx0ACAmkJV0DAPICAB0ACAmPJV0DAPICAAYABglBI0chAPMBAAAA.Fuzzy:BAAALgAECgUJBAABLgAFFAQJDAAUALEgAA==.Fuzzytotems:BAAALgAECgkJEAAAAA==.',
['Få']='Fång:BAAALgAECggJEAAAAA==.',
Ga='Galadenn:BAAALgADCgcJDAAAAA==.Galgar:BAAALgADCgkJCQAAAA==.Garo:BAABLgAECn88AAIPAAkJ8x+OAwDLAgAPAAkJ8x+OAwDLAgAAAA==.',
Ge='Getlnmyvan:BAACLgAFFH8KAAIJAAQJNhwkLABdAQAJAAQJNhwkLABdAQAuAAQKfyoAAgkACQm4IFMTAM4CAAkACQm4IFMTAM4CAAAA.',
Gh='Ghanima:BAAALgAECgEJAQABLgAFFAMJDQAMACQUAA==.Ghoulgranny:BAAALgADCgMJAwAAAA==.Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.Gile:BAAALgAECgIJAwABLgAECgkJIAASAI8LAA==.Gisul:BAAALgAECgMJAwAAAA==.',
Gl='Glert:BAABLgAECn8YAAIXAAgJzA8cngCaAQAXAAgJzA8cngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQFAAkJcAZ1OgApAQAFAAkJcAZ1OgApAQAEAAYJAwS8NQD3AAAbAAYJUAIxVQDiAAAAAA==.Goinsolo:BAABLgAECn8gAAMQAAkJkBF7PgDnAQAQAAkJkBF7PgDnAQARAAYJ4wL/QgC3AAAAAA==.Goldentusk:BAABLgAECn8vAAQHAAkJ/Q6tBwBOAQAHAAgJsA6tBwBOAQAGAAgJngvbCQAVAQAhAAEJAAl3GQAdAAAAAA==.Goldhawk:BAAALgADCgYJBgAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMHAAgJzBnyHwBCAgAHAAgJzBnyHwBCAgAGAAUJeQ6eTQDzAAAAAA==.Gorecrush:BAAALgADCgEJAQABLgAFFAQJHAAFAAYXAA==.Gorvax:BAABLgAECn82AAMTAAkJJhv/CwBMAgATAAkJJhv/CwBMAgASAAMJ4xDwKgF1AAAAAA==.',
Gr='Grimnyx:BAAALgADCgYJCwAAAA==.Grimstout:BAAALgAECgEJAQAAAA==.Grimthos:BAAALgADCgUJBQAAAA==.Gripe:BAAALgAECgYJDAAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAkJLQAQADQeAA==.',
Gw='Gwenledyr:BAABLgAECn9HAAQCAAkJux7SBABIAgACAAgJmB3SBABIAgABAAkJzxV2PADpAQAaAAcJtRv9BwDPAQAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hayzell:BAAALgADCgEJAQAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAFFAMJDQAMACQUAA==.Heimthrall:BAABLgAECn80AAIJAAkJpw2TbgCRAQAJAAkJpw2TbgCRAQAAAA==.Hekatee:BAABLgAECn80AAIBAAcJqxE+CgBTAQABAAcJqxE+CgBTAQAAAA==.Hekkruk:BAAALgAECgMJAwABLgAFFAYJHAAhANUdAA==.Hekus:BAEALgAECgYJCQABLgAECgcJEQANAAAAAA==.Hemesia:BAAALgAECgEJAgAAAA==.Henshin:BAABLgAECn82AAMHAAkJaSSRCwAGAwAHAAgJWSSRCwAGAwAGAAgJ8BPwIQC5AQAAAA==.Herak:BAABLgAECn8hAAIRAAcJxwuzKwBFAQARAAcJxwuzKwBFAQAAAA==.Hermey:BAAALgAECgYJBwAAAA==.Hermiecrabbs:BAAALgAECgMJAwAAAA==.',
Hi='Highchairjr:BAABLgAECn8nAAMaAAgJZhreEwASAQABAAUJfBn8iQAmAQAaAAcJABfeEwASAQAAAA==.Hildaelf:BAAALgAECgYJDwABLgAECgkJJAAKAPEiAA==.',
Ho='Hojdeeznuts:BAABLgAECn8vAAMIAAgJSx64FQBfAgAIAAgJSx64FQBfAgAJAAYJ6gbF6gDRAAAAAA==.Holyfudge:BAAALgAECgMJAwAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJBgAAAA==.Honeymilk:BAAALgAECgUJBQABLgAFFAYJGAAQAC4XAA==.Horazi:BAAALgAECgEJAQABLgAFFAQJDgAIAAMiAA==.Horohöro:BAAALgAFFAQJBAABLgAFFAQJDgAOAMsZAA==.Hotlinebling:BAAALgAECgMJAwAAAA==.Hovp:BAAALgADCgUJBQAAAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hà']='Hàwk:BAAALgAECgEJAQAAAA==.',
['Hè']='Hèimdall:BAABLgAECn8YAAIJAAYJSwkkNAB3AAAJAAYJSwkkNAB3AAAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ib='Ibuprofen:BAAALgAECgEJBAAAAA==.',
Ic='Icelynn:BAAALgAECgYJBgABLgAFFAgJNwAQAHcXAA==.',
Ii='Iil:BAABLgAECn8xAAMXAAkJtBjgNQBBAgAXAAkJtBjgNQBBAgAcAAEJFRSWGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECgkJMQAXALQYAA==.',
Is='Isahuntudown:BAAALgAECgEJAQAAAA==.Istor:BAAALgAECgUJDQAAAA==.',
Ja='Jalir:BAAALgADCgEJAQAAAA==.Jaxxia:BAABLgAECn8tAAIIAAkJFg9sNQB7AQAIAAkJFg9sNQB7AQAAAA==.',
Jb='Jblaze:BAAALgAECgYJEAAAAA==.',
Je='Jellzilla:BAAALgAECgEJAQAAAA==.Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAABLgAECn8XAAIVAAgJDBXfIgCaAQAVAAgJDBXfIgCaAQAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgAECgMJBAAAAA==.',
Jo='Joesphkony:BAAALgAECgIJBAAAAA==.',
Ju='Ju:BAABLgAECn8fAAIUAAYJxhsxLwC/AQAUAAYJxhsxLwC/AQAAAA==.Juzodots:BAAALgAECgEJAgAAAA==.Juzomido:BAACLgAFFH8dAAIRAAcJ7BYQBwCcAQARAAcJ7BYQBwCcAQAuAAQKfygAAhEACQmQHHkEANMCABEACQmQHHkEANMCAAAA.',
['Jã']='Jãina:BAAALgAECgEJAQAAAA==.',
Ka='Kadann:BAAALgAECgEJAgAAAA==.Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn88AAIVAAkJLRoEDwBZAgAVAAkJLRoEDwBZAgAAAA==.Kaline:BAACLgAFFH8FAAIdAAQJfxSwFADdAAAdAAQJfxSwFADdAAAuAAQKfx8AAx0ACAllHagGAFsCAB0ACAllHagGAFsCAAYABwnuE7IGAGEBAAAA.Karupmyazz:BAAALgADCgEJAQAAAA==.Karupted:BAABLgAECn8dAAIQAAcJvgrLhwAvAQAQAAcJvgrLhwAvAQAAAA==.Katianna:BAABLgAECn81AAILAAkJvB2MDgDgAgALAAkJvB2MDgDgAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAABLgAECn8oAAIJAAkJvxQfEwA6AQAJAAkJvxQfEwA6AQAAAA==.Keek:BAAALgADCgEJAQAAAA==.Keola:BAAALgAECgUJBQABLgAECgkJCgANAAAAAA==.Kerra:BAAALgADCgYJBwAAAA==.',
Kh='Khalli:BAABLgAECn8zAAMbAAkJOxlbFQAqAgAbAAgJ5hhbFQAqAgAFAAEJVwcSkwAoAAAAAA==.Khalwena:BAAALgAECgQJBQAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBwAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Killossus:BAAALgAECgQJBAAAAA==.Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAABLgAECn8ZAAMJAAcJVRL9jgBUAQAJAAcJVRL9jgBUAQAKAAIJ0wAsWQAdAAAAAA==.Kissesnhugs:BAAALgAECgEJAQAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.Kiwirage:BAEALgAECgcJEAABLgAECgkJKAAMAOwbAA==.Kizent:BAAALgAECgYJDgAAAA==.Kizlock:BAAALgAECgMJBAAAAA==.',
Kl='Klaya:BAAALgAECgYJCgABLgAFFAMJAwANAAAAAA==.Klaylee:BAAALgAECgEJAgABLgAFFAMJAwANAAAAAA==.',
Ko='Koraena:BAACLgAFFH8IAAIQAAMJ0gqXOADEAAAQAAMJ0gqXOADEAAAuAAQKfx8AAhAACQn9EhsKAMcBABAACQn9EhsKAMcBAAAA.Koronuss:BAABLgAFFH8GAAISAAMJuw9QpQDPAAASAAMJuw9QpQDPAAAAAA==.',
Kr='Krivgar:BAAALgAECgcJDwAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgQJBgAAAA==.',
Ku='Kulrig:BAACLgAFFH8cAAQFAAQJBhftFQA1AQAFAAQJBhftFQA1AQAEAAMJawStOgCXAAAbAAMJ/gUjKACDAAAuAAQKf0wABAUACAl6HK0TADICAAUACAl6HK0TADICABsABwlMGnAFAJABAAQAAQkNBjiHACQAAAAA.Kurri:BAAALgAECgUJBQAAAA==.Kurwa:BAAALgAECgUJBQAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kâ']='Kârnage:BAAALgAECgEJAgAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgkJJQAQAOAPAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lichi:BAAALgAECgEJAgAAAA==.Lightjohn:BAAALgADCgkJFgAAAA==.Liliac:BAAALgADCgEJAQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgAECgYJDgABLgAECgkJJAAKAPEiAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunagaux:BAAALgAECgQJBAAAAA==.Lunalei:BAAALgAECgIJAgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
['Lò']='Lòki:BAAALgAFFAEJAQAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAgAAAA==.Mahoraga:BAABLgAECn8cAAIfAAkJmB3IFwBKAgAfAAkJmB3IFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malcanious:BAAALgAECgQJBQAAAA==.Malganon:BAABLgAECn83AAIJAAkJnB0jHACcAgAJAAkJnB0jHACcAgAAAA==.Malifecent:BAAALgADCgQJBAAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Marfeil:BAAALgAECgIJAwAAAA==.Margarrann:BAAALgAFFAIJAgABLgAFFAQJHAAFAAYXAA==.Markymark:BAAALgADCgYJBgAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Marzanna:BAABLgAECn8WAAIXAAYJfgcMJgC4AAAXAAYJfgcMJgC4AAAAAA==.Mashpewtater:BAAALgAECgcJEgAAAA==.Mashpwntato:BAAALgAECgYJDQAAAA==.Mathelmana:BAABLgAECn83AAMCAAkJ/RjgBABGAgACAAkJYhfgBABGAgABAAcJThFecQBXAQABLgAFFAQJFwALAJ0cAA==.Matthious:BAAALgAECgEJAQAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Melissandre:BAAALgAECggJDQAAAA==.Mellwin:BAAALgAECgQJBAAAAA==.Mezthyr:BAAALgADCggJCAAAAA==.',
Mi='Miliandra:BAAALgADCgkJEAAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Miniarrow:BAAALgADCggJCAAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8vAAIFAAkJYRLtHQDWAQAFAAkJYRLtHQDWAQAAAA==.Miseral:BAACLgAFFH8MAAIWAAMJHR6CEgAPAQAWAAMJHR6CEgAPAQAuAAQKf0kAAhYACQkCIkcFAO4CABYACQkCIkcFAO4CAAAA.Mison:BAAALgAECgMJAwABLgAECggJCwANAAAAAA==.Missfrost:BAAALgAFFAEJAQAAAA==.Mitzy:BAAALgAFFAEJAQAAAA==.Mizbeheaven:BAAALgAECgEJAgABLgAECgkJDgANAAAAAA==.',
Mo='Moganchee:BAABLgAECn8dAAMXAAkJtgTjmABHAQAXAAkJtgTjmABHAQAiAAcJCgJmCADiAAAAAA==.Mole:BAAALgAECgEJAQAAAA==.Moobloom:BAAALgADCgEJAQABLgAECgkJLQAIABYPAA==.Mooeck:BAAALgAECgUJCQAAAA==.Moostafer:BAAALgAECgMJAwABLgAECgkJLAASACYhAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAQJHAAFAAYXAA==.Morghella:BAABLgAECn9EAAIQAAkJWB/BEQDDAgAQAAkJWB/BEQDDAgAAAA==.Morhsa:BAAALgAECgYJDQAAAA==.Morney:BAAALgAECgUJBgAAAA==.Morticiaa:BAAALgAECgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgAECgIJAwAAAA==.Mysticjaina:BAABLgAECn8dAAIMAAkJVxA8BwBgAQAMAAkJVxA8BwBgAQABLgAFFAMJBgAGAHMFAA==.Mythros:BAAALgAECgcJCQAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJEwAAAA==.Nesmae:BAAALgAECggJEQABLgAFFAYJGAAQAC4XAA==.',
Ni='Nightwitch:BAABLgAECn87AAIRAAkJswe1AwBiAQARAAkJswe1AwBiAQAAAA==.Nimuen:BAAALgADCgMJBgABLgAECgcJFQAYABMHAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8YAAIQAAYJLhfiFgBiAQAQAAYJLhfiFgBiAQAuAAQKf0MAAhAACQkkJKwBABkDABAACQkkJKwBABkDAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Nosferatuu:BAAALgADCgYJBgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECgkJDwAAAA==.Nyxari:BAAALgADCgQJBAAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAFFAIJAgAAAA==.',
Ol='Oleyinka:BAAALgAECgcJDgAAAA==.',
Om='Omnissiah:BAABLgAECn81AAMbAAkJ9hS3GAAGAgAbAAkJ9hS3GAAGAgAEAAIJHQYjcABJAAAAAA==.',
On='Once:BAABLgAECn8iAAMJAAcJUxv6TQDdAQAJAAcJUxv6TQDdAQAIAAUJdBKdEgBwAAAAAA==.Oneyedemon:BAAALgADCggJCQAAAA==.',
Op='Opaths:BAABLgAECn8sAAMSAAgJJiHMIACFAgASAAgJJiHMIACFAgAjAAIJzRA3LQBuAAAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ot='Otand:BAABLgAECn8cAAILAAkJFSHzAABcAwALAAkJFSHzAABcAwAAAA==.',
Ov='Overfrosty:BAABLgAECn81AAIKAAkJTSRiAQA9AwAKAAkJTSRiAQA9AwAAAA==.',
Pa='Paumaie:BAAALgADCgcJCgABLgAFFAMJDQAMACQUAA==.',
Pe='Peng:BAABLgAECn8VAAQkAAkJTw/qIQAgAQAkAAgJ3g/qIQAgAQAlAAEJYwuyfgArAAAeAAEJhQIltwAdAAAAAA==.',
Pi='Pinenuts:BAAALgAECgEJAQAAAA==.Pisanuca:BAAALgAECgIJAgAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAFFAMJBgAIADkTAA==.Pormethius:BAAALgADCgYJBgAAAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Preysight:BAAALgADCgYJBgABLgAECgkJEAANAAAAAA==.Priedorei:BAAALgAECgUJBQAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwABLgAFFAUJBQALAKsRAA==.',
Ps='Psyberollin:BAAALgAECgcJBwABLgAECgkJCgANAAAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgYJCAAAAA==.',
Pv='Pvp:BAABLgAECn8iAAMIAAkJ9hPTHAAdAgAIAAkJ9hPTHAAdAgAJAAEJywykpAEsAAAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Ragnios:BAAALgAECgEJAQABLgAFFAMJDQAMACQUAA==.Rahtas:BAAALgADCgYJCQAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAABLgAECn8jAAMUAAgJtiOIBwAmAwAUAAgJtiOIBwAmAwAVAAIJ0wUvkQA/AAAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8sAAIIAAkJPhliGABEAgAIAAkJPhliGABEAgAAAA==.Raydoink:BAAALgAECgYJBgAAAA==.',
Re='Reighan:BAAALgADCgUJBwAAAA==.Renka:BAAALgAECgQJCAAAAA==.Revolting:BAABLgAFFH8bAAIDAAcJzxRfLwBoAQADAAcJzxRfLwBoAQAAAA==.Reze:BAAALgAECgIJAwABLgAFFAMJCQACAEUfAA==.Rezme:BAAALgADCgkJFAAAAA==.',
Rh='Rhaeny:BAAALgAECgEJAQAAAA==.Rhâine:BAAALgAECgEJAQAAAA==.',
Ri='Rianne:BAAALgAECgUJDwAAAA==.Rithia:BAAALgAECgQJBAAAAA==.Rizeen:BAAALgAECgYJEwAAAA==.',
Ro='Rokkmag:BAAALgADCgEJAQABLgAFFAQJHAAFAAYXAA==.Rose:BAAALgAECgQJBQAAAA==.Rowanbow:BAABLgAECn8UAAMHAAgJSwehlgCFAAAHAAcJIQehlgCFAAAGAAEJNgXWKgAXAAAAAA==.',
Ru='Ruikay:BAAALgAECgIJAgAAAA==.Rumi:BAAALgADCgcJBwAAAA==.Rutane:BAAALgADCggJCAAAAA==.',
['Ré']='Rédd:BAABLgAECn88AAMHAAkJ8RqYEgC4AgAHAAkJ8RqYEgC4AgAGAAUJsAeqZQCGAAAAAA==.',
Sa='Saberhawk:BAABLgAECn8gAAIQAAcJ6hDAcQBdAQAQAAcJ6hDAcQBdAQAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sailarmoon:BAAALgAECgYJBgABLgAECgkJVAABAJwcAA==.Sakee:BAAALgAECgEJAQABLgAECgYJDQANAAAAAA==.Sakurazuka:BAABLgAECn9UAAIBAAkJnByYAgCQAgABAAkJnByYAgCQAgAAAA==.Salaminizer:BAAALgAECgEJBAAAAA==.Samidudu:BAACLgAFFH8GAAIdAAQJchHNEgCPAAAdAAQJchHNEgCPAAAuAAQKfxgAAh0ABwlJFX8hAEMBAB0ABwlJFX8hAEMBAAAA.Sanath:BAABLgAECn8kAAIYAAkJwQ7TLACJAQAYAAkJwQ7TLACJAQAAAA==.Sanctusdeus:BAAALgAFFAEJAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgkJOAARAO0YAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIGAAcJdiRQHwAFAgAGAAcJdiRQHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8uAAIPAAkJAiORAQAdAwAPAAkJAiORAQAdAwAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAQJHAAFAAYXAA==.Sevotharte:BAAALgAECgcJDwAAAA==.',
Sg='Sgtmoose:BAAALgAECgUJCgAAAA==.Sgtox:BAAALgAECgUJBgAAAA==.',
Sh='Shadeswift:BAAALgAECgYJCgAAAA==.Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgUJCAAAAA==.Shadowofhate:BAABLgAECn8ZAAIaAAcJ4xqJAQDgAQAaAAcJ4xqJAQDgAQABLgAECgkJJQAiAJEeAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shampain:BAAALgAECgEJAwAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8WAAILAAQJOyNMHwB4AQALAAQJOyNMHwB4AQAuAAQKfzIAAgsACQkGJgMBAMwDAAsACQkGJgMBAMwDAAAA.Shioban:BAAALgAECgIJAgAAAA==.Shizu:BAAALgAECgQJBQAAAA==.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIhAAkJHRmrCQAnAgAhAAkJHRmrCQAnAgAAAA==.Shootermacge:BAAALgAECgQJBgABLgAECgkJGwAJAFwSAA==.Shoun:BAAALgADCgkJCQAAAA==.',
Si='Sib:BAAALgAECgMJBAAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Silverlight:BAACLgAFFH8HAAMKAAMJjwoiCQCCAAAKAAMJjwoiCQCCAAAJAAIJjgQAVABrAAAuAAQKfxoABAkABwmnEUkVACYBAAkABwmnEUkVACYBAAgAAwlJGywLAOwAAAoAAwlOD28MAIgAAAEuAAUUBAkcAAUABhcA.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgcJDwAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sleasem:BAAALgADCgIJAgAAAA==.Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8kAAIJAAgJ2RlsPgAMAgAJAAgJ2RlsPgAMAgAAAA==.Snke:BAAALgADCgcJBwABLgAECggJJAAJANkZAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8tAAISAAkJvR+tHgDJAgASAAkJvR+tHgDJAgAAAA==.Soleron:BAAALgADCgQJCAAAAA==.Somah:BAAALgADCgEJAQAAAA==.Sonofgods:BAABLgAECn8fAAIQAAkJGRWmSgDBAQAQAAkJGRWmSgDBAQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAABLgAECn8WAAIBAAcJ5hVDCACEAQABAAcJ5hVDCACEAQABLgAECgkJLQADACcRAA==.Soulsummoner:BAAALgADCggJCAAAAA==.',
Sp='Spectrahl:BAABLgAECn8sAAIMAAgJQRLGMgBxAQAMAAgJQRLGMgBxAQABLgAFFAYJGAAQAC4XAA==.Spedspidspud:BAABLgAECn8cAAIDAAcJ0SAFKgAhAgADAAcJ0SAFKgAhAgAAAA==.Spelledwrong:BAAALgAECgEJAQAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgkJLgAFAJEQAA==.',
St='Stall:BAAALgAECgIJAQABLgAECgYJBQANAAAAAA==.Starrbuck:BAABLgAECn82AAMHAAkJ3gwCXwAZAQAHAAgJtwoCXwAZAQAGAAEJrwJlpwAZAAAAAA==.Steakumss:BAAALgAECgUJDAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8cAAIRAAkJjBNdFgDvAQARAAkJjBNdFgDvAQAAAA==.Stryke:BAABLgAECn8rAAIbAAkJjBq7EgBHAgAbAAkJjBq7EgBHAgAAAA==.',
Su='Sumiya:BAAALgAECgQJBAAAAA==.Sunfury:BAAALgAECgQJBgAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgMJBQAAAA==.Suterareta:BAABLgAECn9XAAMmAAkJBhgJAQAzAgAmAAkJVxcJAQAzAgAWAAYJBhiPPwD9AAAAAA==.',
Sy='Sylareith:BAABLgAECn8hAAQUAAcJbxldNgCbAQAUAAYJRRhdNgCbAQAVAAcJ4xSuSQDaAAAOAAUJSxMGWACpAAAAAA==.Synderella:BAACLgAFFH8IAAImAAQJJwXvBQCfAAAmAAQJJwXvBQCfAAAuAAQKfxUAAyYABwlwEPICAD0BACYABwlwEPICAD0BABYAAQlBBWqBAB0AAAAA.Syntara:BAABLgAECn81AAIPAAkJPCATBAC2AgAPAAkJPCATBAC2AgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taggalongg:BAAALgADCgYJBgAAAA==.Tailung:BAAALgADCgMJAwAAAA==.Taksun:BAABLgAECn9FAAIdAAkJpBreCABeAgAdAAkJpBreCABeAgAAAA==.Tandas:BAAALgAFFAMJBAAAAA==.Tandy:BAAALgAECgkJEwAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn84AAITAAkJzg0OIABUAQATAAkJzg0OIABUAQAAAA==.Tav:BAABLgAFFH8XAAMlAAUJyh3yEABXAQAlAAUJyh3yEABXAQAkAAIJnxqHIwB+AAAAAA==.',
Te='Terrence:BAAALgADCgEJAQAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8kAAMKAAkJ8SL5BACmAgAKAAkJ8SL5BACmAgAJAAUJUBbU3ADiAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.Theoryhazit:BAAALgAECgEJAQAAAA==.Thewarwithin:BAAALgADCggJCAAAAA==.Thighvoltage:BAAALgAECgEJAQABLgAECgkJLQADACcRAA==.',
Ti='Tialndreyvia:BAAALgAECgQJBwAAAA==.Tianara:BAACLgAFFH8GAAMIAAMJOROhLwC4AAAIAAMJOROhLwC4AAAJAAIJtRlzjgCVAAAuAAQKfxcAAwgACAmNIfIEAB0DAAgACAmNIfIEAB0DAAoABAk+FWwqALgAAAAA.Titania:BAAALgADCgQJBAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJDwAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Toffeecocoa:BAAALgADCgMJAwAAAA==.Tok:BAAALgAECgQJBQAAAA==.Tokeheals:BAAALgAECgQJBAAAAA==.Tokens:BAABLgAECn8YAAIiAAkJ8xluAAALAgAiAAkJ8xluAAALAgAAAA==.Tolerabull:BAABLgAECn8uAAQIAAkJ2x61DwCdAgAIAAgJHh61DwCdAgAKAAYJjwgoKQDPAAAJAAEJexSggQE8AAAAAA==.Torrent:BAABLgAFFH8FAAILAAUJqxGkFQAcAQALAAUJqxGkFQAcAQAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trebeck:BAAALgAECgEJAgABLgAECgkJJAAKAPEiAA==.Trixxe:BAACLgAFFH8TAAIDAAQJ0RDMJwDgAAADAAQJ0RDMJwDgAAAuAAQKfz4AAgMACQniHdMBALECAAMACQniHdMBALECAAAA.Trojaan:BAABLgAECn8VAAIeAAkJMgXWXgDZAAAeAAkJMgXWXgDZAAAAAA==.Trostani:BAAALgAECgQJBAAAAA==.Trulisha:BAACLgAFFH8NAAIMAAMJJBRyHAC2AAAMAAMJJBRyHAC2AAAuAAQKfxcAAgwACAkzG3AwAJ0BAAwACAkzG3AwAJ0BAAAA.Trurala:BAAALgAFFAMJAwAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgMJAwAAAA==.',
Ue='Uelfaen:BAAALgADCgYJBwAAAA==.',
Un='Undolf:BAABLgAECn8vAAMQAAgJsyB+BAB4AgAQAAgJzh9+BAB4AgARAAYJdxvZAgCXAQAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8kAAITAAkJkQbGKwD8AAATAAkJkQbGKwD8AAAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAABLgAECn8lAAIFAAcJHwiXRQD5AAAFAAcJHwiXRQD5AAAAAA==.',
Va='Vacum:BAAALgAECgYJDwABLgAECgcJIgAJAFMbAA==.Vaderon:BAAALgAECgcJDAAAAA==.Vadimas:BAAALgAECgEJAQAAAA==.Vaelanar:BAAALgAECgYJCAAAAA==.Vagann:BAAALgADCgUJBQAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vanillacocoa:BAAALgADCgIJAgAAAA==.Vayine:BAACLgAFFH8QAAIKAAQJfwdbDQClAAAKAAQJfwdbDQClAAAuAAQKfysAAgoACQkxFKIVAHYBAAoACQkxFKIVAHYBAAAA.Vaynitee:BAAALgADCgcJEQAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECgkJNgATACYbAA==.Veridesh:BAAALgAECgcJEQABLgAFFAQJHAAFAAYXAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAABLgAECn8VAAMYAAkJHQsDTgD1AAAYAAcJzAkDTgD1AAAZAAYJug1YIwDUAAAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAFFAMJAwABLgAFFAUJEQALABolAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8kAAITAAkJQhOcGACeAQATAAkJQhOcGACeAQAAAA==.',
Vy='Vynlash:BAAALgADCgYJAQAAAA==.',
['Vì']='Vìcious:BAACLgAFFH8HAAMRAAIJnApLKwCHAAARAAIJnApLKwCHAAAQAAEJrwU+rwA9AAAuAAQKfzYAAxAACAn/FfFMALsBABAACAk3FfFMALsBABEABwloFOsfAJ0BAAAA.',
Wa='Wangwingwong:BAAALgAECgEJAQABLgAECgcJHAADANEgAA==.Warpaths:BAAALgAECgEJAQABLgAECgkJLAASACYhAA==.Watah:BAAALgADCgQJBAAAAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgABLgAFFAMJAwANAAAAAA==.Wide:BAACLgAFFH8ZAAIJAAUJDCSqBwB4AQAJAAUJDCSqBwB4AQAuAAQKfyoAAwkACAl8JFYXAN0CAAkACAl8JFYXAN0CAAoAAwmaJe8EAEQBAAAA.Wigglyears:BAABLgAECn8uAAMFAAkJkRDiIwCqAQAFAAkJkRDiIwCqAQAEAAcJwQ8iKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgQJBwAAAA==.',
Wo='Wowaddict:BAAALgAECgkJBwAAAA==.',
Ws='Wselfwulf:BAAALgAECgUJEgABLgAECgkJJAAKAPEiAA==.',
Xa='Xanadaria:BAAALgAECgkJDgAAAA==.Xanalhano:BAAALgADCgYJBgAAAA==.Xanalluna:BAAALgAECgQJAwABLgAECgkJDgANAAAAAA==.Xandrelyra:BAAALgADCgMJBQABLgAECgkJDgANAAAAAA==.Xanvarani:BAAALgAECgkJCQABLgAECgkJDgANAAAAAA==.',
Xe='Xenwilder:BAAALgAECgEJAQAAAA==.Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgAECgUJBgAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgAECggJDwAAAA==.Yakushimaru:BAABLgAECn82AAIGAAkJFSGoBgDsAgAGAAkJFSGoBgDsAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgIJAwAAAA==.',
Za='Zaare:BAAALgAECgEJAgAAAA==.',
Ze='Zefren:BAABLgAFFH8ZAAIJAAQJ5h0LPwAtAQAJAAQJ5h0LPwAtAQAAAA==.Zeith:BAABLgAECn8mAAIkAAkJXRYTEADmAQAkAAkJXRYTEADmAQAAAA==.Zephystara:BAAALgAECgQJBAABLgAECgkJDgANAAAAAA==.Zeriul:BAAALgAECgUJCgAAAA==.Zeta:BAAALgAECgQJBgABLgAFFAYJEAADABkaAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJDQAAAA==.',
Zu='Zurik:BAACLgAFFH8cAAIhAAYJ1R2IAgBbAQAhAAYJ1R2IAgBbAQAuAAQKfy0AAiEACQm6IKoCAPgCACEACQm6IKoCAPgCAAAA.',
Zy='Zyphoros:BAAALgADCgkJCwAAAA==.',
['Âr']='Ârchangel:BAAALgADCgQJBAAAAA==.',
['Äz']='Äzúlà:BAABLgAECn8kAAIXAAkJkxhRBQBVAgAXAAkJkxhRBQBVAgAAAA==.',
['År']='Årrowz:BAAALgAECgIJBAAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAABLgAECn8UAAIJAAcJ9wfC0QDwAAAJAAcJ9wfC0QDwAAAAAA==.',
['Ìt']='Ìta:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðeadlymyth:BAAALgAECgQJBAAAAA==.',
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
