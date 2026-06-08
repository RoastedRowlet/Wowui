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

local lookup = {'Warrior-Fury','Warrior-Protection','Paladin-Protection','Warlock-Affliction','Priest-Discipline','Priest-Shadow','Priest-Holy','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Frost','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Warrior-Arms','Evoker-Devastation','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','Evoker-Preservation','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=46,date='2026-06-07',data={Aa='Aaricus:BAAALgAECgYJCAAAAA==.',
Ab='Aberdine:BAACLgAFFH8VAAIBAAUJjBDgHwAmAQABAAUJjBDgHwAmAQAuAAQKfy4AAwEACQnlGNgZABkCAAEACQnlGNgZABkCAAIAAglnDbBSACsAAAAA.',
Ac='Accar:BAABLgAECn8kAAIDAAgJ6xD4FAB2AQADAAgJ6xD4FAB2AQAAAA==.Achu:BAAALgAFFAIJBAABLgAFFAQJHgAEAPMlAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCgkJFwAAAA==.',
Ag='Agrias:BAABLgAECn8jAAQFAAgJCBh6EgBFAgAFAAgJCBh6EgBFAgAGAAIJfQmobABeAAAHAAEJrw77bAAsAAAAAA==.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Amaltheah:BAAALgAECgQJBAAAAA==.Ambry:BAAALgAECgQJEgABLgAECgkJJQAIAL8QAA==.Ambryosia:BAABLgAECn8lAAIIAAkJvxCuawCNAQAIAAkJvxCuawCNAQAAAA==.',
An='Andras:BAAALgAECgIJAgAAAA==.Angerßane:BAAALgADCgMJAwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgkJEgABLgAECgcJFQAJAPgFAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAYJFwAKAMEZAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAILAAYJYBFDMAD1AAALAAYJYBFDMAD1AAAAAA==.',
Aw='Awfulshotz:BAABLgAECn8WAAIMAAkJHRwnSAC/AQAMAAkJHRwnSAC/AQABLgAECgYJIAANAOAUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8aAAMCAAkJJBdLFgCrAQACAAkJJBdLFgCrAQABAAQJKRBdbQCiAAAAAA==.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgkJHQAOAG4eAA==.Bcwarrior:BAAALgAECgYJCQABLgAECgkJHQAOAG4eAA==.',
Be='Bearymanalow:BAAALgAECgEJAQAAAA==.Belgrove:BAAALgADCgEJAQAAAA==.',
Bh='Bheap:BAAALgAECgQJCAAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAPAAAAAA==.',
Bl='Blizzaga:BAAALgAECgYJDgAAAA==.',
Bo='Boiardi:BAAALgAECgYJEAAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAABLgAECn8VAAIQAAYJ5hODSQBgAQAQAAYJ5hODSQBgAQAAAA==.',
Bu='Burrgold:BAAALgAECggJDgAAAA==.',
Ca='Cadya:BAAALgAECgYJCQABLgAFFAMJCAARANEKAA==.',
Ce='Celticwoman:BAABLgAECn8jAAMSAAcJywmGkgASAQASAAcJywmGkgASAQATAAUJyQR5OwDGAAAAAA==.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8rAAIUAAgJvgbVBwAIAQAUAAgJvgbVBwAIAQAAAA==.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAIQAAIJGCI2OgDBAAAQAAIJGCI2OgDBAAABLgAFFAQJDAAVAE8WAA==.',
Cl='Clockie:BAACLgAFFH8eAAMEAAQJ8yXlAwBLAQAEAAMJ9iXlAwBLAQASAAMJaiHcTwAcAQAuAAQKfzsABAQACQneJLAGAAACABIABwkJJEQkAEgCAAQABglTJbAGAAACABMABAkKH7MjADsBAAAA.Clõüd:BAABLgAECn8hAAIIAAgJMhDwdwB0AQAIAAgJMhDwdwB0AQABLgAFFAYJEgANAIgMAA==.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
Cy='Cynthigosa:BAAALgAECgQJBAAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAPAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECgkJEwAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgUJDQAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAPAAAAAA==.Dinkster:BAAALgAECgMJAwAAAA==.',
Dk='Dkcloud:BAABLgAECn8dAAIJAAcJUx+oRQDrAQAJAAcJUx+oRQDrAQABLgAFFAYJEgANAIgMAA==.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8MAAIWAAIJMyEKFQDGAAAWAAIJMyEKFQDGAAABLgAFFAQJDAAVAE8WAA==.Duoduomoney:BAABLgAFFH8JAAMBAAMJlBY9LADtAAABAAMJlBY9LADtAAAXAAIJ4w4rMgB4AAABLgAFFAQJDAAVAE8WAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8MAAIGAAMJlhWwHwDhAAAGAAMJlhWwHwDhAAABLgAFFAQJHgAEAPMlAA==.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAABLgAECn8YAAIQAAgJvQcDYgAGAQAQAAgJvQcDYgAGAQAAAA==.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgAECgEJAQAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJDgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIYAAYJkwqxEQDkAAAYAAYJkwqxEQDkAAAAAA==.Fintan:BAAALgADCgMJAwAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCgAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJCgABLgAECgkJMwARAHoiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAPAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAAIAM8UAA==.',
Gl='Glorr:BAAALgAECgYJBgAAAA==.',
Go='Gonamanar:BAAALgAECgcJBQAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgkJDwAAAA==.',
Gr='Grimfall:BAABLgAECn8sAAQZAAgJ7hwlEwALAgAZAAgJNBslEwALAgAMAAUJch7bQACsAQAaAAUJLBNOTwASAQAAAA==.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMIAAgJzxRSawCOAQAIAAgJzxRSawCOAQADAAMJMwW4SAA8AAAAAA==.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgALAGARAA==.',
Ha='Hastor:BAAALgADCgcJBwAAAA==.',
He='Hellgrazer:BAAALgAECgYJDwAAAA==.',
Hi='Highlowe:BAAALgAECgcJCgAAAA==.Hikiru:BAAALgAECgcJBwAAAA==.',
Ho='Hollowbane:BAABLgAECn8oAAMbAAkJdxh/DwApAgAbAAkJdxh/DwApAgAcAAMJpBYcFgDBAAAAAA==.Holydh:BAAALgAECgIJAgAAAA==.Holydragonn:BAAALgAFFAEJAQAAAA==.Holylock:BAAALgAFFAIJAgAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAABLgAFFH8FAAIdAAIJRQXoawBWAAAdAAIJRQXoawBWAAAAAA==.Holywarrior:BAAALgAFFAMJBAAAAA==.Holyymonk:BAAALgAFFAIJAgAAAA==.Holyyseeker:BAAALgAFFAEJAQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAgJGAARACEbAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8SAAINAAYJiAzAPQBpAQANAAYJiAzAPQBpAQAuAAQKfzcAAg0ACQn9H/MYABUDAA0ACQn9H/MYABUDAAAA.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAABLgAECn8VAAIJAAcJ+AWiugD9AAAJAAcJ+AWiugD9AAAAAA==.Jonnytsunami:BAABLgAFFH8HAAIeAAQJ9he8DAAXAQAeAAQJ9he8DAAXAQAAAA==.',
Ju='Juicycow:BAAALgAECgYJCwAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8jAAIfAAcJgyaPAQCdAgAfAAcJgyaPAQCdAgAuAAQKfyMAAx8ACAnRJksCAHcDAB8ACAnRJksCAHcDACAAAQlVITh4AFcAAAAA.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgYJCwAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8OAAIeAAQJdgewGgCmAAAeAAQJdgewGgCmAAAuAAQKfxkAAh4ACAmuETkPAIgBAB4ACAmuETkPAIgBAAAA.Kittyhawk:BAAALgAECggJEAAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBgAAAA==.Klixx:BAAALgAECgYJDAAAAA==.',
Ko='Konexx:BAAALgAECgIJAgAAAA==.',
Ks='Kstab:BAABLgAECn8bAAIbAAcJLBuIGgAuAgAbAAcJLBuIGgAuAgAAAA==.',
Ku='Kuromeow:BAABLgAFFH8HAAINAAIJYRl9NgC9AAANAAIJYRl9NgC9AAAAAA==.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAABLgAECn8eAAIhAAYJeRM5FgBlAQAhAAYJeRM5FgBlAQAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAQJFgAOACwmAA==.Lesiania:BAAALgAECgEJAwABLgAECgYJCAAPAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8oAAMGAAgJShdzHQDSAQAGAAgJShdzHQDSAQAHAAMJ7wTvbAB2AAAAAA==.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAMJCwAfAFcZAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECggJEAAAAA==.',
Lu='Lucyah:BAAALgAECgYJCgAAAA==.',
Ma='Makshifu:BAAALgAFFAEJAQABLgAFFAQJDAAVAE8WAA==.Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAIRAAYJSgo5igAPAQARAAYJSgo5igAPAQABLgAECggJIAAIAM8UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Megumyxd:BAAALgAECgMJAwAAAA==.Menion:BAABLgAECn8cAAMIAAkJZhuLJgCMAgAIAAkJZhuLJgCMAgADAAUJQgybMACZAAAAAA==.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAcJIAAJABwfAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgQJCAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgcJEQABLgAECgkJQQAgAIAgAA==.',
Mo='Monkpig:BAACLgAFFH8YAAIfAAQJZx5wFQBlAQAfAAQJZx5wFQBlAQAuAAQKfyoAAh8ACQntHzQNAFwCAB8ACQntHzQNAFwCAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAILAAYJTRWSKgAZAQALAAYJTRWSKgAZAQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAPAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAPAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAIRAAgJuBziHQCeAgARAAgJuBziHQCeAgAAAA==.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAIOAAYJnBa6HABlAQAOAAYJnBa6HABlAQAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECgkJKwAJAMgUAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAPAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJCQAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyCLMACGAQABAAYJlyCLMACGAQACAAQJnAvkPgBpAAAAAA==.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAIJAAcJrB1CSwARAgAJAAcJrB1CSwARAgABLgAFFAMJBAAPAAAAAA==.',
Ra='Raythe:BAABLgAECn8hAAILAAcJ6BW9IgBRAQALAAcJ6BW9IgBRAQAAAA==.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAQJDgAeAHYHAA==.',
Ru='Ruck:BAAALgAFFAEJAQAAAA==.Rucker:BAABLgAECn8kAAMCAAkJZR1vBwCAAgACAAkJZR1vBwCAAgABAAEJWAIVtQAdAAABLgAFFAEJAQAPAAAAAA==.Ruckkin:BAAALgAECgMJBgABLgAFFAEJAQAPAAAAAA==.Rucksy:BAABLgAECn8oAAMDAAgJoB0RBQCrAgADAAgJoB0RBQCrAgAIAAMJ/hG3/QCZAAABLgAFFAEJAQAPAAAAAA==.Ruckuhs:BAAALgADCgkJDAABLgAFFAEJAQAPAAAAAA==.Ruxsi:BAAALgAECgUJCAABLgAFFAEJAQAPAAAAAA==.',
Ry='Ryan:BAABLgAECn8iAAMIAAkJvR2cKgBNAgAIAAcJnCOcKgBNAgAiAAgJeyAbHwAAAgAAAA==.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAPAAAAAA==.',
Se='Seraphae:BAAALgAECgEJAgAAAA==.Sereb:BAAALgAECgUJBwAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBwAAAA==.Shankzmcgee:BAABLgAECn8cAAIbAAYJcQp+NgDrAAAbAAYJcQp+NgDrAAABLgAECggJIAAIAM8UAA==.Shardik:BAAALgAECgYJEAAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgAECgQJBQAAAA==.Shiftyone:BAAALgADCgMJAwAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAPAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shrussy:BAAALgADCgMJAwAAAA==.Shèrlock:BAABLgAECn8qAAISAAkJDxjZIABaAgASAAkJDxjZIABaAgAAAA==.',
Si='Silverfox:BAABLgAFFH8MAAMVAAQJTxajHQAgAQAVAAQJTxajHQAgAQAdAAIJKBryVgCQAAAAAA==.',
Sk='Skippydippy:BAAALgAECgQJCwAAAA==.Skye:BAAALgAECgcJBQAAAA==.Skylin:BAAALgAECgEJBAAAAA==.',
Sl='Sleezee:BAAALgAECgQJCQAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgAECgYJDgAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAMJCwAfAFcZAA==.',
St='Stargasm:BAABLgAFFH8HAAIHAAIJXw8vKABtAAAHAAIJXw8vKABtAAAAAA==.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgAECgUJCAAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8JAAIQAAIJtw7LUgBxAAAQAAIJtw7LUgBxAAABLgAFFAMJCwAfAFcZAA==.',
Sy='Syleyn:BAAALgAECgUJBwABLgAFFAQJFgAOACwmAA==.Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgYJDQAAAA==.',
Ta='Taft:BAABLgAECn8wAAMjAAkJjBOzGwDgAQAjAAkJjBOzGwDgAQAQAAEJDQwp2AAoAAAAAA==.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJHwAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAgAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAABLgAECn8cAAIBAAcJuhQqLwCNAQABAAcJuhQqLwCNAQAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAABLgAECn8WAAIVAAYJBhW3OgA9AQAVAAYJBhW3OgA9AQAAAA==.Tritin:BAABLgAECn8WAAIIAAgJmAYHxQD2AAAIAAgJmAYHxQD2AAAAAA==.Trotndot:BAAALgADCgQJBAAAAA==.',
Tu='Tugginmypuda:BAAALgAECgQJBAAAAA==.',
Tw='Twiltock:BAAALgAECgYJDAAAAA==.Twizztyd:BAAALgAECgYJDgAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8sAAINAAgJ6wUdqQAoAQANAAgJ6wUdqQAoAQAAAA==.Valiria:BAACLgAFFH8IAAIRAAMJzBZ8VwDWAAARAAMJzBZ8VwDWAAAuAAQKfx8AAhEACQldGa0pABkCABEACQldGa0pABkCAAAA.Varzul:BAAALgADCgYJCwABLgAECgIJAgAPAAAAAA==.',
Ve='Velieda:BAABLgAECn8mAAMIAAgJ0xHOhgBYAQAIAAgJBw7OhgBYAQADAAYJtxKnHwAMAQAAAA==.',
Vi='Vie:BAAALgAECgYJBgAAAA==.Vindication:BAACLgAFFH8WAAIOAAQJLCboCgCyAQAOAAQJLCboCgCyAQAuAAQKfyoAAg4ACAlvIC4HAL0CAA4ACAlvIC4HAL0CAAAA.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wafflez:BAAALgAECgIJAgAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.Winteranne:BAAALgAECgEJAQAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
['Wÿ']='Wÿcked:BAAALgAECgUJCAAAAA==.',
Xi='Xiaobao:BAABLgAFFH8KAAIeAAQJ3Q5SEgDbAAAeAAQJ3Q5SEgDbAAAAAA==.Xiaoduoduo:BAACLgAFFH8OAAMIAAMJoB9aUwD5AAAIAAMJoB9aUwD5AAAiAAEJuCNHPwBbAAAuAAQKfyoAAggACQmiI/AQANYCAAgACQmiI/AQANYCAAEuAAUUBAkMABUATxYA.Xiaomak:BAAALgADCgQJBAABLgAFFAQJDAAVAE8WAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAABLgAECn8iAAIIAAgJzAbYrQAYAQAIAAgJzAbYrQAYAQAAAA==.',
Za='Zabz:BAAALgAECgEJAgABLgAECgkJNgAIAMAgAA==.',
Ze='Zeroskills:BAABLgAECn8kAAMbAAkJ/Qf7IQB3AQAbAAkJ/Qf7IQB3AQAcAAIJSwQZIQBPAAAAAA==.',
Zu='Zulinar:BAABLgAECn8UAAIdAAYJcgu8bwD/AAAdAAYJcgu8bwD/AAAAAA==.Zumoku:BAAALgAECgYJAwAAAA==.',
['Às']='Àsmodeus:BAABLgAECn87AAQeAAkJzBNYEADUAQAeAAkJzBNYEADUAQAjAAIJrgWmegBHAAAQAAEJMQqI2wAmAAAAAA==.',
['Æn']='Ænimá:BAAALgADCgEJAQAAAA==.',
['ßi']='ßiggysmalls:BAAALgADCgUJBQAAAA==.',
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
