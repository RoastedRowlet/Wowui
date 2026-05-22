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

local lookup = {'Warrior-Fury','Warrior-Protection','Paladin-Protection','DeathKnight-Frost','Priest-Discipline','Priest-Holy','Paladin-Retribution','Unknown-Unknown','DemonHunter-Havoc','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Druid-Restoration','Warlock-Affliction','DeathKnight-Unholy','Evoker-Augmentation','Warrior-Arms','Priest-Shadow','Evoker-Devastation','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=46,date='2026-05-17',data={Aa='Aaricus:BAAALgAECgYJCAAAAA==.',
Ab='Aberdine:BAACLgAFFH8OAAIBAAQJXQtQGQAaAQABAAQJXQtQGQAaAQAuAAQKfyoAAwEACQmpGIonACACAAEACQmpGIonACACAAIAAglnDdFDACwAAAAA.',
Ac='Accar:BAABLgAECn8aAAIDAAcJJhEJFQA1AQADAAcJJhEJFQA1AQAAAA==.Achu:BAAALgAFFAIJAgABLgAFFAQJCQAEAPwbAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCggJDQAAAA==.',
Ag='Agrias:BAABLgAECn8WAAMFAAgJHBdzDgA+AgAFAAgJHBdzDgA+AgAGAAEJrA5wWwAvAAAAAA==.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Ambry:BAAALgAECgQJDgABLgAECggJIgAHAPYOAA==.Ambryosia:BAABLgAECn8iAAIHAAgJ9g6OeQA9AQAHAAgJ9g6OeQA9AQAAAA==.',
An='Andras:BAAALgAECgIJAgAAAA==.Angerßane:BAAALgADCgMJAwAAAA==.',
Ap='Apocketheory:BAAALgADCgcJBwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgcJCgABLgAECgYJCwAIAAAAAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAUJEAAEAIceAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAIJAAYJYBG6IgAJAQAJAAYJYBG6IgAJAQAAAA==.',
Aw='Awfulshotz:BAAALgAECgMJAwABLgAECgYJIAAKAOAUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8aAAMCAAkJHRdLFgCrAQACAAkJHRdLFgCrAQABAAQJKRC6VwCmAAAAAA==.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgcJGwALADIfAA==.Bcwarrior:BAAALgAECgYJCQABLgAECgcJGwALADIfAA==.',
Be='Belgrove:BAAALgADCgEJAQAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAIAAAAAA==.',
Bl='Blizzaga:BAAALgAECgQJCQAAAA==.',
Bo='Boiardi:BAAALgAECgEJAQAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgYJDQAAAA==.',
Bu='Burrgold:BAAALgAECgcJDgAAAA==.',
Ca='Cadya:BAAALgAECgYJBwABLgAECggJHQAMAHkVAA==.',
Ce='Celticwoman:BAABLgAECn8jAAMNAAcJygmjewAVAQANAAcJygmjewAVAQAOAAUJyQR5OwDGAAAAAA==.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8dAAIPAAYJcwWdBwDEAAAPAAYJcwWdBwDEAAAAAA==.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAIQAAIJGCL1LADIAAAQAAIJGCL1LADIAAABLgAFFAMJDgAHAKAfAA==.',
Cl='Clockie:BAACLgAFFH8SAAMRAAMJBiaKCABuAAANAAIJ0iUOKwDFAAARAAEJbyaKCABuAAAuAAQKfzsABBEACQnaJPIDABICAA0ABwkDJO8ZAFcCABEABglWJfIDABICAA4ABAkKH7MjADsBAAEuAAUUBAkJAAQA/BsA.Clõüd:BAABLgAECn8bAAIHAAgJgw/rXgB3AQAHAAgJgw/rXgB3AQABLgAFFAUJEQAKABkNAA==.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAIAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECggJEwAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgUJCwAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAIAAAAAA==.',
Dk='Dkcloud:BAABLgAECn8cAAISAAcJUx+2NADzAQASAAcJUx+2NADzAQABLgAFFAUJEQAKABkNAA==.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8KAAITAAIJMyEKFQDGAAATAAIJMyEKFQDGAAABLgAFFAMJDgAHAKAfAA==.Duoduomoney:BAABLgAFFH8GAAMUAAIJfBMdHQCEAAABAAIJfBPlLACXAAAUAAIJ4w4dHQCEAAABLgAFFAMJDgAHAKAfAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8JAAIVAAIJVQ64DwCnAAAVAAIJVQ64DwCnAAABLgAFFAQJCQAEAPwbAA==.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAAALgAECggJDgAAAA==.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgAECgEJAQAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJCgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIWAAYJkwrEDQD3AAAWAAYJkwrEDQD3AAAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCQAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJBgABLgAECgkJMwAMAHYiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAIAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAAHAM4UAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgYJBAAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgcJDAAAAA==.',
Gr='Grimfall:BAABLgAECn8sAAQXAAgJ7hxbDQAcAgAXAAgJNBtbDQAcAgAYAAUJch7bQACsAQAZAAUJLBNOTwASAQAAAA==.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMHAAgJzhTiUACZAQAHAAgJzhTiUACZAQADAAMJMwXJOQA8AAAAAA==.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgAJAGARAA==.',
Hi='Hikiru:BAAALgADCgkJHgAAAA==.',
Ho='Hollowbane:BAABLgAECn8eAAMaAAgJIBYKFwCZAQAaAAgJexUKFwCZAQAbAAMJpBbTEQDMAAAAAA==.Holydh:BAAALgAECgEJAQAAAA==.Holydragonn:BAAALgADCgQJBAAAAA==.Holylock:BAAALgAECgQJCAAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAAALgAFFAIJAwAAAA==.Holywarrior:BAAALgAFFAEJAQAAAA==.Holyymonk:BAAALgAECgEJAQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAgJFAAMAKcZAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8RAAIKAAUJGQ3CRgAuAQAKAAUJGQ3CRgAuAQAuAAQKfzQAAgoACQn9H0sTALYCAAoACQn9H0sTALYCAAAA.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAAALgAECgYJCwAAAA==.Jonnytsunami:BAAALgAECgQJBwAAAA==.',
Ju='Juicycow:BAAALgAECgYJCwAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8eAAIcAAYJoSaEAQA8AgAcAAYJoSaEAQA8AgAuAAQKfyAAAxwACAnPJksCAHcDABwACAnPJksCAHcDAB0AAQlVIdJdAFoAAAAA.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgYJCgAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8KAAIeAAMJgQiSDwCSAAAeAAMJgQiSDwCSAAAuAAQKfxkAAh4ACAmuETkPAIgBAB4ACAmuETkPAIgBAAAA.Kittyhawk:BAAALgAECggJDwAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBQAAAA==.Klixx:BAAALgAECgEJAgAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8YAAIaAAcJLBuIGgAuAgAaAAcJLBuIGgAuAgAAAA==.',
Ku='Kuromeow:BAABLgAFFH8HAAIKAAIJYRl9NgC9AAAKAAIJYRl9NgC9AAAAAA==.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAAALgAECgYJEAAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAMJDAALAAkkAA==.Lesiania:BAAALgAECgEJAQABLgAECgYJCAAIAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8eAAMVAAgJTRdJFQDeAQAVAAgJTRdJFQDeAQAGAAMJ7wTvbAB2AAAAAA==.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAMJCQAcALcVAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgYJDQAAAA==.',
Lu='Lucyah:BAAALgAECgMJBAAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAIMAAYJSgo5igAPAQAMAAYJSgo5igAPAQABLgAECggJIAAHAM4UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMHAAkJZhuLJgCMAgAHAAkJZhuLJgCMAgADAAUJQgxuJgCcAAAAAA==.Meowmeowmeow:BAAALgADCgcJBwAAAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgMJBAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgYJBwABLgAECggJNwAdAGsjAA==.',
Mo='Monkpig:BAACLgAFFH8QAAIcAAMJNh5PHwAEAQAcAAMJNh5PHwAEAQAuAAQKfyoAAhwACQntH6EJAGkCABwACQntH6EJAGkCAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAIJAAYJTRV/HwAkAQAJAAYJTRV/HwAkAQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAIAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAIAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAIMAAgJuBziHQCeAgAMAAgJuBziHQCeAgAAAA==.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAILAAYJnBa6HABlAQALAAYJnBa6HABlAQAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECgkJKwASAMcUAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAIAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJBgAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyBqIwCZAQABAAYJlyBqIwCZAQACAAQJnAuVMgBzAAAAAA==.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAISAAcJrB1CSwARAgASAAcJrB1CSwARAgABLgAFFAMJBAAIAAAAAA==.',
Ra='Raythe:BAABLgAECn8dAAIJAAcJ5hX1GQBVAQAJAAcJ5hX1GQBVAQAAAA==.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAMJCgAeAIEIAA==.',
Ru='Rucker:BAABLgAECn8hAAMCAAkJfRvWBgBgAgACAAkJfRvWBgBgAgABAAEJWAIVtQAdAAAAAA==.Ruckkin:BAAALgAECgMJAwABLgAECgkJIQACAH0bAA==.Rucksy:BAABLgAECn8kAAMDAAgJZh0RBQCrAgADAAgJZh0RBQCrAgAHAAMJ/hG3/QCZAAABLgAECgkJIQACAH0bAA==.Ruxsi:BAAALgAECgUJCAABLgAECgkJIQACAH0bAA==.',
Ry='Ryan:BAABLgAECn8XAAMfAAcJ+yFGKgDgAQAfAAYJPyFGKgDgAQAHAAYJmCL4PQDRAQAAAA==.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAIAAAAAA==.',
Se='Seraphae:BAAALgADCgQJBwAAAA==.Sereb:BAAALgAECgQJBAAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBAAAAA==.Shankzmcgee:BAABLgAECn8cAAIaAAYJcQrbKQD5AAAaAAYJcQrbKQD5AAABLgAECggJIAAHAM4UAA==.Shardik:BAAALgAECgEJAQAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCgkJGAAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAIAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shrussy:BAAALgADCgMJAwAAAA==.Shèrlock:BAABLgAECn8VAAINAAgJig9GTACFAQANAAgJig9GTACFAQAAAA==.',
Si='Silverfox:BAAALgAECggJCAABLgAFFAMJDgAHAKAfAA==.',
Sk='Skippydippy:BAAALgAECgQJCwAAAA==.Skylin:BAAALgAECgEJAwAAAA==.',
Sl='Sleezee:BAAALgAECgMJBgAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgAECgUJBQAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAMJCQAcALcVAA==.',
St='Stargasm:BAAALgAFFAEJAQAAAA==.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgAECgUJBQAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8JAAIQAAIJtw5uPgCAAAAQAAIJtw5uPgCAAAABLgAFFAMJCQAcALcVAA==.',
Sy='Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgEJAQAAAA==.',
Ta='Taft:BAABLgAECn8vAAIgAAkJjBNyFADnAQAgAAkJjBNyFADnAQAAAA==.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJFQAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAgAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAAALgAECgYJCwAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAAALgAECgYJDwAAAA==.Tritin:BAAALgAECgYJDwAAAA==.',
Tw='Twiltock:BAAALgAECgYJDAAAAA==.Twizztyd:BAAALgAECgEJAQAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8gAAIKAAYJCAacvgDXAAAKAAYJCAacvgDXAAAAAA==.Valiria:BAABLgAECn8ZAAIMAAcJnRxZMQA1AgAMAAcJnRxZMQA1AgAAAA==.Varzul:BAAALgADCgYJCwABLgAECgIJAgAIAAAAAA==.',
Ve='Velieda:BAABLgAECn8cAAMHAAgJ7Q82ZwBkAQAHAAgJBg42ZwBkAQADAAYJEBC+HADmAAAAAA==.',
Vi='Vindication:BAACLgAFFH8MAAILAAMJCSQ6DQAzAQALAAMJCSQ6DQAzAQAuAAQKfyMAAgsACAkoIC4HAL0CAAsACAkoIC4HAL0CAAAA.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
Xi='Xiaobao:BAAALgAFFAIJAgAAAA==.Xiaoduoduo:BAACLgAFFH8OAAMHAAMJoB+bMQAYAQAHAAMJoB+bMQAYAQAfAAEJuCO2MABhAAAuAAQKfyoAAgcACQmiIxYJAPECAAcACQmiIxYJAPECAAAA.Xiaomak:BAAALgADCgQJBAAAAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAAALgAECgYJDwAAAA==.',
Za='Zabz:BAAALgADCgQJBwABLgAECggJJwAHAHsgAA==.',
Ze='Zeroskills:BAABLgAECn8hAAMaAAkJ/Ad8GQCBAQAaAAkJ/Ad8GQCBAQAbAAIJSwTWGgBUAAAAAA==.',
Zu='Zulinar:BAAALgAECgYJBwAAAA==.Zumoku:BAAALgADCgkJKQAAAA==.',
['Às']='Àsmodeus:BAABLgAECn8oAAQeAAkJcxHkDQCoAQAeAAkJcxHkDQCoAQAgAAEJ8gaedAAoAAAQAAEJMQqSvQAmAAAAAA==.',
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
