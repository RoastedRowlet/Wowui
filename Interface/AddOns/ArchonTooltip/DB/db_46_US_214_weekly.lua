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

local lookup = {'Warrior-Fury','Warrior-Protection','Paladin-Protection','Warlock-Affliction','Priest-Discipline','Priest-Shadow','Priest-Holy','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Frost','DeathKnight-Blood','Druid-Restoration','Unknown-Unknown','Druid-Balance','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Warrior-Arms','Evoker-Devastation','Hunter-Survival','Hunter-Marksmanship','Monk-Brewmaster','Shaman-Restoration','Shaman-Enhancement','Rogue-Subtlety','Rogue-Assassination','Druid-Guardian','Monk-Windwalker','Evoker-Preservation','Paladin-Holy',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aaricus:BAAALgAECgYJCAAAAA==.',
Ab='Aberdine:BAACLgAFFH8jAAIBAAcJIhWWDwCJAQABAAcJIhWWDwCJAQAuAAQKfy4AAwEACQnlGOAbAA8CAAEACQnlGOAbAA8CAAIAAglnDUpWACsAAAAA.',
Ac='Accar:BAABLgAECn8oAAIDAAgJUxG6FQB4AQADAAgJUxG6FQB4AQAAAA==.Achu:BAAALgAFFAIJBAABLgAFFAQJHgAEAPMlAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgAECgcJEQAAAA==.',
Ag='Agrias:BAABLgAECn8jAAQFAAgJCBi7EwBCAgAFAAgJCBi7EwBCAgAGAAIJfQl+cgBcAAAHAAEJrw6JcQAsAAAAAA==.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.Alindriel:BAAALgADCgEJAQAAAA==.',
Am='Amaltheah:BAAALgAECgQJBAAAAA==.Ambry:BAAALgAECgQJEgABLgAECgkJKQAIAL8QAA==.Ambryosia:BAABLgAECn8pAAIIAAkJvxBFaQCcAQAIAAkJvxBFaQCcAQAAAA==.',
An='Andras:BAAALgAECgMJBgAAAA==.Angerßane:BAAALgADCgMJAwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgkJEgABLgAECgkJGAAJANMHAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAgJGQAKAIATAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAILAAYJYBFRMwD0AAALAAYJYBFRMwD0AAAAAA==.',
Aw='Awfulshotz:BAACLgAFFH8FAAIMAAMJRw0rNgC6AAAMAAMJRw0rNgC6AAAuAAQKfyEAAgwACQmwIdIFABICAAwACQmwIdIFABICAAEuAAQKBgkhAA0AqxUA.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8aAAMCAAkJJBdLFgCrAQACAAkJJBdLFgCrAQABAAQJKRB1cgCfAAAAAA==.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgkJHgAOAG4eAA==.Bcshaman:BAAALgAECggJDgABLgAECgkJHgAOAG4eAA==.Bcwarrior:BAAALgAECgYJCQABLgAECgkJHgAOAG4eAA==.',
Be='Bearymanalow:BAAALgAECgEJAQAAAA==.Beauvine:BAAALgAECgYJBwAAAA==.Belgrove:BAAALgADCgEJAQAAAA==.',
Bh='Bheap:BAABLgAECn8cAAIPAAgJPyEVAQDzAgAPAAgJPyEVAQDzAgAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAQAAAAAA==.',
Bl='Blizzaga:BAAALgAECggJEAAAAA==.',
Bo='Bobbyperu:BAAALgAECgEJAQAAAA==.Bodhì:BAAALgAECgEJAQAAAA==.Boiardi:BAAALgAECgYJEAAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAABLgAECn8oAAMPAAkJmBi1AgAgAgAPAAkJmBi1AgAgAgARAAUJVQ93CwDBAAAAAA==.',
Bu='Burrgold:BAAALgAECggJDgAAAA==.',
Ca='Cadya:BAAALgAFFAIJAgABLgAFFAMJCgASAIMLAA==.Carpathiá:BAAALgAECgEJAQAAAA==.Causinghavoc:BAAALgADCggJCAAAAA==.',
Ce='Celticwoman:BAABLgAECn8jAAMTAAcJywlcmAAMAQATAAcJywlcmAAMAQAUAAUJyQR5OwDGAAAAAA==.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgAECgMJAwAAAA==.Chickenugget:BAABLgAECn8yAAIVAAkJoweVCAAEAQAVAAkJoweVCAAEAQAAAA==.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAIPAAIJGCJuPAC9AAAPAAIJGCJuPAC9AAABLgAFFAQJDAAWAE8WAA==.',
Cl='Clockie:BAACLgAFFH8eAAMEAAQJ8yV4BABEAQAEAAMJ9iV4BABEAQATAAMJaiFyWAAWAQAuAAQKfzsABAQACQneJEwHAP4BABMABwkJJGkmAEQCAAQABglTJUwHAP4BABQABAkKH7MjADsBAAAA.Cloudyeyez:BAAALgAECgEJAQABLgAECgcJDAAQAAAAAA==.Clõüd:BAACLgAFFH8HAAIIAAQJBxUzFQAzAQAIAAQJBxUzFQAzAQAuAAQKfyQAAggACAluFdd9AHMBAAgACAluFdd9AHMBAAEuAAUUBwkTAA0ADgwA.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
Cy='Cynthigosa:BAAALgAECgQJBAAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAQAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECgkJEwAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Deathsprings:BAAALgADCggJDAAAAA==.Delita:BAAALgAECgUJDQAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAQAAAAAA==.Dil:BAAALgADCgUJBQAAAA==.Dinkster:BAAALgAECgMJBQAAAA==.',
Dk='Dkcloud:BAABLgAECn8eAAIJAAgJ2h3wMQA2AgAJAAgJ2h3wMQA2AgABLgAFFAcJEwANAA4MAA==.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8MAAIXAAIJMyEKFQDGAAAXAAIJMyEKFQDGAAABLgAFFAQJDAAWAE8WAA==.Duoduomoney:BAABLgAFFH8JAAMBAAMJlBZYMQDqAAABAAMJlBZYMQDqAAAYAAIJ4w5HOAB3AAABLgAFFAQJDAAWAE8WAA==.',
Dy='Dyabolik:BAAALgAECgUJBgAAAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8MAAIGAAMJlhX9IgDdAAAGAAMJlhX9IgDdAAABLgAFFAQJHgAEAPMlAA==.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAABLgAECn8cAAIPAAgJvQc2ZQAFAQAPAAgJvQc2ZQAFAQAAAA==.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgAECgEJAQAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJDgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIZAAYJkwqvEgDgAAAZAAYJkwqvEgDgAAAAAA==.Fintan:BAAALgADCgMJAwAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJEAAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.Gattzu:BAAALgAECgcJDgAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAQAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAAIAM8UAA==.',
Gl='Glorr:BAAALgAECgcJBwAAAA==.',
Go='Gonamanar:BAAALgAECgcJBQAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgkJDwAAAA==.',
Gr='Grandreaper:BAAALgADCggJEgAAAA==.Grimfall:BAABLgAECn8sAAQaAAgJ7hx+FAAAAgAaAAgJNBt+FAAAAgAMAAUJch7bQACsAQAbAAUJLBNOTwASAQAAAA==.Grimtyr:BAAALgAECgEJAQAAAA==.Gripology:BAAALgAECgMJAwABLgAFFAMJCwAcAFcZAA==.Grëëdo:BAABLgAECn8gAAMIAAgJzxQMcQCMAQAIAAgJzxQMcQCMAQADAAMJMwUeTAA8AAAAAA==.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgALAGARAA==.',
Ha='Hastor:BAAALgADCgcJBwAAAA==.',
He='Hellgrazer:BAABLgAECn8XAAITAAYJ9wfsHQBkAAATAAYJ9wfsHQBkAAAAAA==.',
Hi='Highlowe:BAABLgAECn8WAAQdAAgJfRwKHQBkAgAdAAYJbiMKHQBkAgAeAAMJKQ03KwCfAAAWAAMJTAeTgQBtAAAAAA==.Hikiru:BAABLgAECn8YAAIKAAgJcBP4AgBKAQAKAAgJcBP4AgBKAQAAAA==.',
Ho='Hoiylight:BAAALgAFFAEJAQAAAA==.Hollowbane:BAACLgAFFH8IAAIfAAMJlAlyKwDUAAAfAAMJlAlyKwDUAAAuAAQKfyoAAx8ACQnWGJkQACYCAB8ACQnWGJkQACYCACAAAwmkFhMXAMEAAAAA.Holydragonn:BAAALgAFFAEJAQAAAA==.Holylock:BAAALgAFFAIJAgAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAABLgAFFH8MAAMdAAMJ3xKXJwCdAAAdAAMJ3xKXJwCdAAAWAAEJewKGOAAqAAAAAA==.Holywarrior:BAAALgAFFAMJBAAAAA==.Holyymonk:BAAALgAFFAIJBAAAAA==.Holyyseeker:BAAALgAFFAEJAQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Hordeareus:BAAALgADCgUJBwAAAA==.Horse:BAAALgAECgYJBwABLgAFFAkJMQALAJckAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imdemonic:BAABLgAECn8UAAISAAkJIBfYAgAcAgASAAkJIBfYAgAcAgAAAA==.Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
It='Itsover:BAAALgADCgcJCAAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8TAAINAAcJDgy9RgBYAQANAAcJDgy9RgBYAQAuAAQKf0AAAg0ACQmhItcJACsDAA0ACQmhItcJACsDAAAA.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAABLgAECn8YAAIJAAkJ0weyxAD4AAAJAAkJ0weyxAD4AAAAAA==.Jonnytsunami:BAABLgAFFH8IAAIhAAQJaBlTDQAlAQAhAAQJaBlTDQAlAQAAAA==.',
Ju='Juicycow:BAAALgAECgcJDAAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.Kariden:BAAALgAECgcJBwAAAA==.',
Ke='Keg:BAACLgAFFH8pAAIcAAgJtCZQAAAmAwAcAAgJtCZQAAAmAwAuAAQKfyMAAxwACAnRJksCAHcDABwACAnRJksCAHcDACIAAQlVITh/AFYAAAAA.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgYJCwAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8OAAIhAAQJdgdZIACcAAAhAAQJdgdZIACcAAAuAAQKfxkAAiEACAmuETkPAIgBACEACAmuETkPAIgBAAAA.Kittyhawk:BAAALgAECggJEwAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBgAAAA==.Klixx:BAAALgAECgYJDAAAAA==.',
Ko='Konexx:BAAALgAECgIJAgAAAA==.',
Ks='Kstab:BAABLgAECn8bAAIfAAcJLBuIGgAuAgAfAAcJLBuIGgAuAgAAAA==.',
Ku='Kuromeow:BAABLgAFFH8HAAINAAIJYRl9NgC9AAANAAIJYRl9NgC9AAAAAA==.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAABLgAECn8kAAMjAAkJihCWEgCfAQAjAAgJdQ+WEgCfAQAZAAIJqgmTBwAyAAAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAQJHQAOACwmAA==.Lesiania:BAAALgAECgEJAwABLgAECgYJCAAQAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lifeordeath:BAAALgADCgYJBgAAAA==.Lightkeeper:BAABLgAECn8pAAMGAAgJJxm8HgDQAQAGAAgJJxm8HgDQAQAHAAMJ7wTvbAB2AAAAAA==.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAMJCwAcAFcZAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lo='Loralia:BAAALgAECgEJBAAAAA==.',
Lr='Lroux:BAAALgAECgkJEgAAAA==.',
Lu='Lucyah:BAAALgAECgcJDgAAAA==.',
Ma='Makewarpvp:BAAALgADCgYJBgAAAA==.Makshifu:BAAALgAFFAIJAwABLgAFFAQJDAAWAE8WAA==.Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Martymcfly:BAAALgAECgQJBAAAAA==.Massacar:BAABLgAECn8YAAISAAYJSgo5igAPAQASAAYJSgo5igAPAQABLgAECggJIAAIAM8UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Megumyxd:BAAALgAECgQJBAAAAA==.Menion:BAABLgAECn8cAAMIAAkJZhuLJgCMAgAIAAkJZhuLJgCMAgADAAUJQgzJMgCYAAAAAA==.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAcJIAAJABwfAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgQJCAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgcJEQABLgAECgkJTQAiAIoiAA==.',
Mo='Monkpig:BAACLgAFFH8YAAIcAAQJZx6dGABeAQAcAAQJZx6dGABeAQAuAAQKfyoAAhwACQntH/oNAFkCABwACQntH/oNAFkCAAAA.Monkyfox:BAAALgAECgcJBgAAAA==.Mooinator:BAAALgADCgYJBgAAAA==.Moosylawless:BAAALgAECgUJCgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAILAAYJTRVBLQAYAQALAAYJTRVBLQAYAQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAQAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAQAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAISAAgJuBziHQCeAgASAAgJuBziHQCeAgAAAA==.',
No='Notash:BAAALgADCgIJAgAAAA==.',
Ny='Nyke:BAAALgAECgMJAwAAAA==.',
Ol='Olaria:BAAALgAECgEJAQAAAA==.Oldspice:BAAALgAECgMJBwAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAIOAAYJnBa6HABlAQAOAAYJnBa6HABlAQAAAA==.Omi:BAAALgAECgQJBAAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECgkJKwAJAMgUAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAQAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJCQAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyA4MgCDAQABAAYJlyA4MgCDAQACAAQJnAvOQQBoAAAAAA==.Perennial:BAAALgAFFAIJAgAAAA==.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.Porunga:BAAALgAECgYJBgAAAA==.',
Qu='Quill:BAABLgAECn8eAAIJAAcJrB1CSwARAgAJAAcJrB1CSwARAgABLgAFFAMJBAAQAAAAAA==.',
Ra='Raythe:BAABLgAECn8iAAILAAcJ6BU1JQBPAQALAAcJ6BU1JQBPAQAAAA==.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Re='Regrowth:BAAALgADCgcJBwAAAA==.',
Ro='Rose:BAAALgAECgcJDgABLgAFFAQJDgAhAHYHAA==.',
Ru='Ruck:BAAALgAFFAEJAQAAAA==.Rucker:BAABLgAECn8sAAMCAAkJmx2RBwCJAgACAAkJmx2RBwCJAgABAAEJWAIVtQAdAAABLgAFFAEJAQAQAAAAAA==.Ruckkin:BAAALgAECgQJBwABLgAFFAEJAQAQAAAAAA==.Rucklin:BAAALgAECgYJBgABLgAFFAEJAQAQAAAAAA==.Ruckomancer:BAAALgADCgYJBgABLgAFFAEJAQAQAAAAAA==.Rucksi:BAAALgAECgcJDQABLgAFFAEJAQAQAAAAAA==.Ruckstitute:BAAALgAECgQJBgABLgAFFAEJAQAQAAAAAA==.Rucksy:BAABLgAECn8pAAMDAAgJ9B8RBQCrAgADAAgJ9B8RBQCrAgAIAAMJ/hG3/QCZAAABLgAFFAEJAQAQAAAAAA==.Ruckuhs:BAAALgADCgkJDAABLgAFFAEJAQAQAAAAAA==.Ruxsi:BAABLgAECn8VAAMcAAYJdhccBAAYAQAcAAYJdhccBAAYAQAiAAIJEgmRFQBLAAABLgAFFAEJAQAQAAAAAA==.',
Ry='Ryan:BAABLgAECn8iAAMIAAkJvR3RLQBJAgAIAAcJnCPRLQBJAgAkAAgJeyCVIAD+AQAAAA==.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAQAAAAAA==.',
Se='Seraphae:BAAALgAECgEJAgAAAA==.Sereb:BAAALgAECgUJBwAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBwAAAA==.Shankzmcgee:BAABLgAECn8cAAIfAAYJcQo9OQDrAAAfAAYJcQo9OQDrAAABLgAECggJIAAIAM8UAA==.Shardik:BAABLgAECn8YAAIRAAYJThFpQAANAQARAAYJThFpQAANAQAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAABLgAECn8XAAIHAAcJYhfTAwC0AQAHAAcJYhfTAwC0AQAAAA==.Shiftyone:BAAALgAECgMJAwAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAQAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shrussy:BAAALgADCgMJAwAAAA==.Shèrlock:BAABLgAECn8yAAITAAkJtRldHAB7AgATAAkJtRldHAB7AgAAAA==.',
Si='Silverfox:BAABLgAFFH8MAAMWAAQJTxbUIQAVAQAWAAQJTxbUIQAVAQAdAAIJKBryXgCNAAAAAA==.',
Sk='Skippydippy:BAAALgAECgQJCwAAAA==.Skye:BAAALgAECgcJBQAAAA==.Skylin:BAAALgAECgEJBAAAAA==.',
Sl='Sleezee:BAAALgAECgQJCgAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgAECgYJDgAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAMJCwAcAFcZAA==.Spirited:BAAALgAECgEJAQAAAA==.',
Ss='Ssjgodxx:BAAALgAECgQJBgABLgAECggJGgASALgcAA==.',
St='Stargasm:BAABLgAFFH8PAAIHAAMJBg+iEwBsAAAHAAMJBg+iEwBsAAAAAA==.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgAECgUJCAAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAACLgAFFH8JAAIPAAIJtw4QWABpAAAPAAIJtw4QWABpAAAuAAQKfxQABCEABgkHE5U6ALsAACEABgn1EpU6ALsAAA8AAQmYEonKADYAABEAAQk2DEsdACsAAAEuAAUUAwkLABwAVxkA.',
Sy='Syleyn:BAAALgAECgYJEAABLgAFFAQJHQAOACwmAA==.Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgYJDQAAAA==.',
Ta='Taft:BAABLgAECn8wAAMRAAkJjBN6HQDdAQARAAkJjBN6HQDdAQAPAAEJDQyB3gAoAAAAAA==.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.Taurentino:BAAALgAECgYJCwAAAA==.',
Te='Terainer:BAAALgADCgEJAQAAAA==.Terrá:BAAALgAECgYJDQAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Theia:BAAALgAECgEJAgAAAA==.Thomassian:BAAALgAECgEJAgAAAA==.Throbbinknob:BAAALgAECgEJAwAAAA==.Thunderjugs:BAAALgAECgYJBgAAAA==.',
Ti='Tibbs:BAAALgAECgcJEwAAAA==.Timewing:BAAALgAECgMJAwAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAABLgAECn8gAAIBAAcJ2hYdLACkAQABAAcJ2hYdLACkAQAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAABLgAECn8WAAIWAAYJBhUSPgA9AQAWAAYJBhUSPgA9AQAAAA==.Tritin:BAABLgAECn8ZAAIIAAkJ/AWezwDzAAAIAAkJ/AWezwDzAAAAAA==.Trotndot:BAAALgADCgQJBAAAAA==.',
Tu='Tugginmypuda:BAAALgAECgQJBAAAAA==.',
Tw='Twiltock:BAAALgAECgYJDAAAAA==.Twizztyd:BAAALgAECgYJDgAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn81AAINAAkJNAb0rAAmAQANAAkJNAb0rAAmAQAAAA==.Valiria:BAACLgAFFH8IAAISAAMJzBYyXwDSAAASAAMJzBYyXwDSAAAuAAQKfx8AAhIACQldGc8rABkCABIACQldGc8rABkCAAAA.Varzul:BAAALgADCgYJCwABLgAECgIJAgAQAAAAAA==.',
Ve='Velieda:BAABLgAECn8mAAMIAAgJ0xHWjgBUAQAIAAgJBw7WjgBUAQADAAYJtxIrIQALAQAAAA==.',
Vi='Vie:BAAALgAECgYJBgAAAA==.Vindication:BAACLgAFFH8dAAMOAAQJLCYwDQCqAQAOAAQJLCYwDQCqAQAKAAEJ3QGQHAAxAAAuAAQKfy8AAg4ACAmKIDQJAH8CAA4ACAmKIDQJAH8CAAAA.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wafflez:BAAALgAECgIJAgAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
We='Wearehorde:BAAALgADCgYJCQAAAA==.',
Wi='Windchaser:BAAALgAECgEJAQAAAA==.Windflower:BAAALgADCgQJBAAAAA==.Winteranne:BAAALgAECgEJAQAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
['Wÿ']='Wÿcked:BAAALgAECgUJCAAAAA==.',
Xi='Xiaobao:BAABLgAFFH8KAAIhAAQJ3Q4sFgDRAAAhAAQJ3Q4sFgDRAAAAAA==.Xiaoduoduo:BAACLgAFFH8OAAMIAAMJoB/MXQD0AAAIAAMJoB/MXQD0AAAkAAEJuCPaQgBZAAAuAAQKfyoAAggACQmiI9ISANICAAgACQmiI9ISANICAAEuAAUUBAkMABYATxYA.Xiaomak:BAAALgADCgQJBAABLgAFFAQJDAAWAE8WAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xx='Xxschafer:BAABLgAECn8mAAIIAAgJHQkIpQAwAQAIAAgJHQkIpQAwAQAAAA==.',
Za='Zabz:BAAALgAECgYJBwABLgAECgkJOwAIANwhAA==.',
Ze='Zeroskills:BAACLgAFFH8FAAIfAAIJ5AKMHwBdAAAfAAIJ5AKMHwBdAAAuAAQKfyQAAx8ACQn9B7wjAHYBAB8ACQn9B7wjAHYBACAAAglLBKQiAE8AAAAA.',
Zu='Zulinar:BAABLgAECn8ZAAIdAAgJIQtAZwAmAQAdAAgJIQtAZwAmAQAAAA==.Zumoku:BAAALgAECgkJCgAAAA==.',
['Às']='Àsmodeus:BAACLgAFFH8LAAIhAAMJewYkFgBrAAAhAAMJewYkFgBrAAAuAAQKfzsABCEACQnME7MRANQBACEACQnME7MRANQBABEAAgmuBXWAAEcAAA8AAQkxCg/iACYAAAAA.',
['Æn']='Ænimá:BAAALgADCgEJAQAAAA==.',
['Çr']='Çryptwalkin:BAAALgAECgEJAQAAAA==.',
['ßi']='ßiggysmalls:BAAALgADCgUJBQAAAA==.',
['ßl']='ßlàke:BAAALgAECgEJAQAAAA==.',
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
