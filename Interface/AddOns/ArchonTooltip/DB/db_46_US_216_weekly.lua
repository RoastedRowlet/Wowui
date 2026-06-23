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

local lookup = {'Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Druid-Guardian','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','DemonHunter-Vengeance',}
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=46,date='2026-06-21',data={Ab='Abeteon:BAAALgAECgEJAQAAAA==.',
Ac='Acinovanth:BAAALgAECgEJAQAAAA==.Acousticjeff:BAAALgAECgYJBgAAAA==.',
Ad='Adwill:BAABLgAECn8vAAIBAAgJ6B8WCgBKAgABAAgJ6B8WCgBKAgAAAA==.',
Ae='Aelvoker:BAACLgAFFH8ZAAQCAAcJuhqKFwCtAQACAAcJsBWKFwCtAQADAAQJPhUNBAAJAQAEAAQJ7gaBEwCQAAAuAAQKfxcABAMACQlFH1EHAHcCAAMABgkkI1EHAHcCAAQABwmdEYkaALcBAAIAAgndGtFKAKkAAAAA.',
Ai='Aindra:BAAALgAECggJEAAAAA==.Airen:BAAALgAECgYJDQAAAA==.',
An='Antidead:BAABLgAECn8gAAMFAAgJOR50BQCfAgAFAAgJOR50BQCfAgAGAAgJ1xM0eAB+AQAAAA==.',
Ap='Apachaler:BAABLgAECn8nAAQHAAkJ+xoeEQCZAgAHAAkJ+xoeEQCZAgAIAAEJNhk/hQBCAAAJAAEJIgktpAAsAAAAAA==.',
Ar='Arathael:BAAALgADCgIJAgAAAA==.Ardyce:BAAALgADCgIJAgAAAA==.Arrae:BAAALgAECgUJAwAAAA==.Arreuws:BAAALgAECgQJBAAAAA==.',
As='Asiansmoliv:BAACLgAFFH8VAAMKAAQJSB+HAwBeAQAKAAQJSB+HAwBeAQALAAIJ5x5lMgCuAAAuAAQKfzQAAwoACQkgJWoAAFEDAAoACQkgJWoAAFEDAAsABQm6HydVAJ0BAAAA.',
Az='Azriel:BAAALgADCgMJBAAAAA==.Azshan:BAAALgADCgQJBAABLgAECgQJCwAMAAAAAA==.',
Ba='Babymager:BAABLgAECn8iAAINAAcJ5QtPuQATAQANAAcJ5QtPuQATAQAAAA==.Babyshamz:BAAALgAECgYJBgAAAA==.Barranphalnx:BAAALgAECgMJBQAAAA==.',
Bb='Bbldrizzy:BAAALgADCgEJAQAAAA==.',
Be='Beartwige:BAAALgADCgYJBgAAAA==.Beefydomo:BAAALgADCgIJAgABLgAECgEJAQAMAAAAAA==.Belladonnà:BAAALgAECgYJDQABLgAECggJIAAOACMRAA==.Betsy:BAAALgAECgQJBAAAAA==.',
Bh='Bhal:BAAALgAECgEJAQAAAA==.',
Bi='Bigpopapump:BAACLgAFFH8WAAIPAAQJxR0bDgBUAQAPAAQJxR0bDgBUAQAuAAQKfzwAAg8ACQnRJRQBAGADAA8ACQnRJRQBAGADAAAA.Bishop:BAAALgADCgMJAwAAAA==.',
Bl='Blackgarden:BAAALgAECgYJDgAAAA==.Bloodhorde:BAAALgAECgEJAQAAAA==.Bloodydak:BAEALgAECgcJBwABLgAECgcJEAAMAAAAAA==.Bluchu:BAEALgAECgEJAQABLgAECgcJEAAMAAAAAA==.',
Bo='Bombasharna:BAAALgAECgIJBAAAAA==.Bonkzx:BAAALgADCgMJAwAAAA==.Booze:BAAALgAECgkJDwAAAA==.',
Br='Brigne:BAAALgADCgYJCwAAAA==.',
Bu='Buddeez:BAACLgAFFH8dAAINAAgJzB3eDwBtAgANAAgJzB3eDwBtAgAuAAQKfysAAg0ACQk/JU0KAHEDAA0ACQk/JU0KAHEDAAAA.Buddiez:BAAALgADCgEJAQAAAA==.Built:BAABLgAECn8eAAQPAAkJ9CBYDAAJAgAPAAgJASFYDAAJAgAQAAMJTBi+fwDoAAARAAEJ2hhogQBBAAAAAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Carrot:BAAALgAECgIJAgAAAA==.',
Ce='Cenwen:BAACLgAFFH8VAAINAAQJYBopSwBKAQANAAQJYBopSwBKAQAuAAQKfycAAg0ACQmVHmlCABQCAA0ACQmVHmlCABQCAAAA.',
Ch='Chaos:BAACLgAFFH8FAAIPAAMJhxpcHADuAAAPAAMJhxpcHADuAAAuAAQKf08AAg8ACQluJegAAGgDAA8ACQluJegAAGgDAAAA.Chonk:BAAALgAECgYJBgAAAA==.Chugginjizz:BAAALgAECgEJAQABLgAFFAgJJgASADEWAA==.',
Cl='Clawreece:BAAALgAECgQJCQAAAA==.',
Co='Conta:BAAALgAECgYJCQAAAA==.',
Cr='Cryingtears:BAABLgAECn8pAAQTAAgJ9A8dOgBiAQATAAgJ9A8dOgBiAQAGAAcJqQYI6QDTAAAFAAEJAAE8WwAYAAAAAA==.',
Cu='Cuchicu:BAABLgAECn9DAAMUAAkJLxytDwDVAgAUAAkJLxytDwDVAgAVAAUJEhJYOgApAQAAAA==.',
Da='Dakkonix:BAEALgAECgcJEAAAAA==.Dakkonixx:BAEALgAECgUJBgABLgAECgcJEAAMAAAAAA==.Damagexx:BAAALgAECgMJBgAAAA==.Darkaged:BAAALgADCgYJBgAAAA==.Darklords:BAAALgAECgMJAwAAAA==.Daviid:BAAALgADCgYJBgAAAA==.',
De='Demigodd:BAAALgADCgIJAgAAAA==.Demonasa:BAAALgADCgIJAgAAAA==.Desim:BAABLgAECn8WAAISAAcJsx6EMwBoAgASAAcJsx6EMwBoAgAAAA==.Dextt:BAABLgAECn8dAAIWAAcJLCIrDgCpAgAWAAcJLCIrDgCpAgAAAA==.Dez:BAACLgAFFH8GAAITAAMJnQp+BgBoAAATAAMJnQp+BgBoAAAuAAQKfyYAAhMACQnJFcYZADgCABMACQnJFcYZADgCAAAA.',
Dk='Dkamp:BAAALgADCgkJGQAAAA==.',
Dm='Dmoney:BAAALgAECgYJBgAAAA==.',
Do='Dondiablo:BAAALgAECgYJDQAAAA==.Doylock:BAAALgAECgUJBQAAAA==.',
Dr='Dragnaballs:BAEALgAECgcJEgABLgAFFAkJRQANAJwgAA==.Drdot:BAAALgAECgEJBAABLgAECggJHwASALsaAA==.Drehd:BAACLgAFFH8KAAIWAAMJvCQkMQAdAQAWAAMJvCQkMQAdAQAuAAQKfy0AAhYACAnVJF4JAB0DABYACAnVJF4JAB0DAAAA.Drewbear:BAAALgAFFAEJAQABLgAFFAQJDAAXANUaAA==.Drewcifer:BAACLgAFFH8MAAIXAAQJ1RrjBwAEAQAXAAQJ1RrjBwAEAQAuAAQKfy0AAhcACQlFIt4LAOgCABcACQlFIt4LAOgCAAEuAAUUBAkMABcA1RoA.Drewwar:BAAALgAECgEJAQABLgAFFAQJDAAXANUaAA==.Dripps:BAAALgAECgYJBgAAAA==.',
Du='Dumalshadows:BAAALgAECgUJBQAAAA==.Dumper:BAAALgADCgEJAQAAAA==.Dumps:BAAALgAECgMJAwAAAA==.',
['Dó']='Dóom:BAAALgAECgUJCQABLgAFFAMJAwAMAAAAAA==.',
['Dü']='Düsk:BAAALgADCgUJBQABLgAECgMJCgAMAAAAAA==.',
Eg='Egoon:BAAALgAECgQJBgAAAA==.',
El='Elarial:BAAALgADCgEJAQAAAA==.Elmerfud:BAAALgAECgYJBwAAAA==.',
En='Enrèk:BAAALgADCgYJBgAAAA==.',
Fa='Falafel:BAACLgAFFH8kAAISAAYJ4CCuIQDqAQASAAYJ4CCuIQDqAQAuAAQKfygAAhIACQlOIuwSAAoDABIACQlOIuwSAAoDAAAA.',
Fi='Fidely:BAAALgADCgEJAQAAAA==.',
Fl='Flop:BAAALgADCgIJAgAAAA==.',
Fo='Fomo:BAAALgADCgYJBgAAAA==.Fornax:BAAALgAECgQJBwABLgAECgcJFwANAA8MAA==.Fotmtrash:BAACLgAFFH8XAAQYAAQJYR5ZFgANAQAZAAQJTBdPJgAYAQAYAAMJbCBZFgANAQAaAAIJ4gQcNAByAAAuAAQKfzQABBkACQk4I/gFACUDABkACQn+H/gFACUDABgACAkZIu8HAMwCABoAAgknCWFaAE4AAAAA.Foxxydots:BAABLgAECn82AAILAAkJ5RjxMAAVAgALAAkJ5RjxMAAVAgAAAA==.',
Fr='Frostitoot:BAABLgAECn8XAAINAAcJDwwLtwAXAQANAAcJDwwLtwAXAQAAAA==.',
Fu='Fupa:BAAALgAECgEJAQAAAA==.',
Ga='Galbsadi:BAABLgAECn8rAAMbAAgJnRTUEgAeAQAbAAcJtQ/UEgAeAQALAAgJNhIhBQCvAAAAAA==.Garrius:BAAALgADCgQJBAAAAA==.',
Ge='Gelfdar:BAAALgAECgEJAQAAAA==.Genie:BAAALgAECgEJAQAAAA==.Gethendriel:BAAALgAECgUJDAAAAA==.Getsuga:BAAALgAECggJCwABLgAECgkJQwASABgiAA==.',
Gh='Ghostmonk:BAABLgAFFH8GAAIJAAMJhAgHKwCjAAAJAAMJhAgHKwCjAAABLgAFFAcJLQASALodAA==.',
Gl='Glaia:BAAALgADCgYJDQAAAA==.',
Go='Goel:BAAALgAECgEJAgAAAA==.',
Gr='Graf:BAABLgAECn8mAAQcAAkJhSHcHABnAgAcAAcJQyLcHABnAgABAAYJPRgFGwAZAQAdAAYJshoPMQC6AAAAAA==.Grafbear:BAAALgADCgQJBAAAAA==.Graflock:BAAALgAECgUJBQAAAA==.Grimzorath:BAAALgAECgYJBgAAAA==.Grox:BAABLgAECn8UAAIcAAYJmg+qTgBsAQAcAAYJmg+qTgBsAQAAAA==.Grudge:BAAALgADCgMJBQAAAA==.',
Gu='Gulpan:BAAALgAFFAEJAQAAAA==.',
Ha='Hackensack:BAAALgAECggJEAAAAA==.Hamtaro:BAAALgAECgYJDAAAAA==.Hawthorne:BAACLgAFFH8HAAIHAAQJygibEABGAAAHAAQJygibEABGAAAuAAQKfyMAAgcACQmkHZMUAHYCAAcACQmkHZMUAHYCAAAA.',
Hi='Hiyabusa:BAABLgAECn8UAAIeAAcJ4BBDLQCWAQAeAAcJ4BBDLQCWAQAAAA==.',
Ho='Hollowboi:BAABLgAECn88AAIIAAkJMiIKBAAJAwAIAAkJMiIKBAAJAwAAAA==.Holygraf:BAAALgAECgcJDgAAAA==.',
Ia='Iamyama:BAAALgAECgUJCQAAAA==.',
Il='Illgaz:BAAALgAECgEJAQAAAA==.',
Io='Ionna:BAAALgADCgcJBwABLgAECgkJQwASABgiAA==.',
Jd='Jdvance:BAAALgAECgYJBgAAAA==.',
Jh='Jhouska:BAAALgAECgcJEAAAAA==.',
Jo='Jormunngandr:BAACLgAFFH8mAAQSAAgJMRZ0GAAdAgASAAcJMRZ0GAAdAgAfAAEJ4AYPBgBMAAAgAAEJAAA4FQBGAAAuAAQKfx8AAhIACQm9IK0RABIDABIACQm9IK0RABIDAAAA.',
Ju='Judgynomnom:BAACLgAFFH8KAAITAAQJmhn8IwABAQATAAQJmhn8IwABAQAuAAQKfxwAAhMACAloJtwJANQCABMACAloJtwJANQCAAAA.',
Jy='Jyggles:BAABLgAECn8nAAIgAAgJ6QFkAwB1AAAgAAgJ6QFkAwB1AAAAAA==.',
Ka='Kavdh:BAACLgAFFH8OAAIXAAUJrBweBQBRAQAXAAUJrBweBQBRAQAuAAQKfywAAhcACQk8JIgDAE8DABcACQk8JIgDAE8DAAAA.',
Ke='Kenpachip:BAAALgAECgUJBQAAAA==.Keyaesh:BAAALgAECgEJAQAAAA==.',
Ki='Kirax:BAAALgAECgEJAQAAAA==.',
Ko='Konataizumi:BAAALgADCgcJCwAAAA==.',
Kr='Kruhks:BAAALgAECgYJCAABLgAFFAMJCgAWALwkAA==.',
Ks='Kshot:BAABLgAECn89AAIPAAkJmR+PBgC4AgAPAAkJmR+PBgC4AgAAAA==.',
La='Lagdalen:BAABLgAECn8aAAIYAAYJExw/HwDKAQAYAAYJExw/HwDKAQAAAA==.Lanachan:BAABLgAECn9IAAIcAAkJ7RgbEwBZAgAcAAkJ7RgbEwBZAgAAAA==.',
Ld='Ldn:BAABLgAECn9GAAINAAkJBxWRAgB8AQANAAkJBxWRAgB8AQAAAA==.',
Le='Lep:BAAALgAECgUJBQAAAA==.',
Li='Lightofdawn:BAAALgAECgEJAQAAAA==.Likai:BAAALgADCgUJBQAAAA==.Lisa:BAAALgADCgcJAQAAAA==.Liz:BAACLgAFFH8GAAIQAAMJYQJ/EAB2AAAQAAMJYQJ/EAB2AAAuAAQKfzgAAhAACQmICbJdAI0BABAACQmICbJdAI0BAAAA.',
Ly='Lylieth:BAABLgAECn87AAILAAkJyBN/PgDiAQALAAkJyBN/PgDiAQAAAA==.Lyndyn:BAAALgADCgIJAgAAAA==.',
Ma='Mather:BAAALgAECgEJAgAAAA==.Mayzel:BAAALgAECgMJBAAAAA==.',
Mi='Microsqueeze:BAAALgADCgkJCQAAAA==.Miriko:BAAALgADCgkJCQAAAA==.',
Mo='Mock:BAACLgAFFH8IAAICAAMJaQKUUgB/AAACAAMJaQKUUgB/AAAuAAQKfx4AAgIACQnxDFYsAIwBAAIACQnxDFYsAIwBAAEuAAQKCQkjABkAqgwA.Mogera:BAAALgADCgMJBQAAAA==.Mouthyhusky:BAABLgAFFH8GAAIQAAQJDgOXXwDlAAAQAAQJDgOXXwDlAAAAAA==.',
Ni='Ninluv:BAAALgAECgQJDgAAAA==.',
Ny='Nyancat:BAAALgAECgEJAQAAAA==.',
Ol='Olaho:BAAALgADCgYJBgAAAA==.',
Om='Omenz:BAAALgADCgIJAgAAAA==.Omey:BAAALgAECgEJBAAAAA==.',
Oo='Oojni:BAAALgADCgYJBgAAAA==.',
Or='Oraine:BAAALgAECgUJBQAAAA==.Ortrazzarn:BAAALgAECgEJAQABLgAECgkJPAAIADIiAA==.',
Pa='Pazzman:BAAALgADCgYJBwAAAA==.',
Pe='Perc:BAAALgAECgQJBAAAAA==.',
Ph='Pharhar:BAABLgAECn81AAMTAAkJWiEpEACXAgATAAkJWiEpEACXAgAGAAUJHRskpgAuAQAAAA==.',
Po='Poppachàdson:BAABLgAECn8dAAIhAAcJ+CDTCABPAgAhAAcJ+CDTCABPAgABLgAFFAMJBgAhABoVAA==.Poppadadson:BAACLgAFFH8GAAIhAAMJGhXuDwDHAAAhAAMJGhXuDwDHAAAuAAQKfxwAAiEABwmBH4kGAI0CACEABwmBH4kGAI0CAAAA.Poppadotson:BAAALgAECgMJAwABLgAFFAMJBgAhABoVAA==.',
Pr='Priceless:BAAALgAECgkJBgAAAA==.',
Pu='Puscifer:BAAALgAECgkJCQAAAA==.',
Qu='Quarrior:BAAALgADCgEJAQABLgAECgMJCgAMAAAAAA==.Quellazaire:BAAALgADCgcJDAAAAA==.Quincar:BAAALgADCgEJAQABLgAECgMJCgAMAAAAAA==.',
Ra='Rafayel:BAAALgAECgIJAgABLgAECgkJQwAUAC8cAA==.Raizel:BAAALgAECgEJAQABLgAECgkJQwAUAC8cAA==.Ravister:BAAALgAECgUJBQABLgAFFAgJIQAaAGkgAA==.',
Re='Rebecknight:BAAALgADCgkJCQABLgAECgkJPAAIADIiAA==.Relic:BAACLgAFFH8iAAQfAAcJ4xF3BAC7AQAfAAYJpBF3BAC7AQASAAEJnBEGFQE+AAAgAAIJxQv8QgAoAAAuAAQKfykAAx8ACQmEHZMCAIwCAB8ACQmEHZMCAIwCABIABgmbF4WCAF4BAAAA.Renk:BAABLgAECn8vAAISAAkJACYPBQBUAwASAAkJACYPBQBUAwAAAA==.Renka:BAAALgAECgUJBQABLgAECgkJLwASAAAmAA==.',
Ro='Ronald:BAABLgAECn8UAAIGAAYJZRrhlgBPAQAGAAYJZRrhlgBPAQAAAA==.Rowdyrebel:BAAALgAECgkJBwAAAA==.Roykevious:BAAALgAECgEJAwAAAA==.',
Sa='Saeyl:BAAALgAECgYJDAABLgAECgkJIAAZAB0KAA==.Saihu:BAAALgADCgEJAQABLgAECgkJQwASABgiAA==.Sammie:BAEALgAECgUJCAABLgAECgcJEAAMAAAAAA==.Sarix:BAAALgAECgQJBAAAAA==.Sarromand:BAAALgAECgUJBQABLgAECgkJPAAIADIiAA==.Savant:BAAALgAECgMJAwAAAA==.Sayl:BAABLgAECn8gAAMZAAkJHQpyNwA1AQAZAAgJjAlyNwA1AQAaAAUJMwgdWQCwAAAAAA==.',
Sc='Scallywinkle:BAAALgAECgcJEAAAAA==.Scrap:BAABLgAECn8aAAMLAAkJ4hqLPgATAgALAAgJcBqLPgATAgAbAAQJeRTgKwAQAQAAAA==.',
Se='Senova:BAAALgAECgIJAgAAAA==.',
Sh='Shadowghoul:BAABLgAECn8WAAIaAAgJbwrSNgA6AQAaAAgJbwrSNgA6AQAAAA==.Shadowydern:BAABLgAECn8oAAMaAAkJlSACCgCuAgAaAAkJlSACCgCuAgAYAAEJ/RBpfwAzAAAAAA==.Shamewow:BAACLgAFFH8aAAIWAAcJ8RVDEwDMAQAWAAcJ8RVDEwDMAQAuAAQKfzMAAhYACQlIHNYWAJMCABYACQlIHNYWAJMCAAAA.Sharkbite:BAAALgAECgQJCwAAAA==.Shrimpboat:BAAALgAECgYJBQAAAA==.',
Si='Sicknnasty:BAACLgAFFH8dAAIgAAYJmBUEEgBqAQAgAAYJmBUEEgBqAQAuAAQKf0oAAyAACQkMIuYHAJoCACAACQkMIuYHAJoCABIACAlRFqlaALYBAAAA.Sicsickly:BAAALgAFFAEJAQAAAA==.',
Sl='Slayerz:BAAALgAECgYJBgAAAA==.',
Sn='Snattch:BAAALgADCgEJAQAAAA==.Snookismalls:BAABLgAECn8jAAMZAAkJqgx4IQDCAQAZAAkJqgx4IQDCAQAaAAcJXwdfRgD2AAAAAA==.',
So='Solarian:BAAALgADCgMJAwAAAA==.Solitary:BAABLgAECn8fAAISAAgJuxrxMAA7AgASAAgJuxrxMAA7AgAAAA==.Sos:BAAALgAECgEJAQAAAA==.',
Sp='Sparkyboo:BAAALgAECgEJAQAAAA==.Speed:BAAALgAECgYJCwAAAA==.Spinach:BAAALgAECgMJAQABLgAECgYJBQAMAAAAAA==.',
St='Starshopping:BAABLgAECn8aAAIXAAgJmiEmAQCWAQAXAAgJmiEmAQCWAQABLgAFFAMJBQAPAIcaAA==.',
Su='Sunari:BAAALgADCgQJBAAAAA==.',
Ta='Taewryn:BAABLgAFFH8FAAMdAAQJQA/VGgDAAAAdAAQJQA/VGgDAAAAcAAEJYgWVVwA7AAABLgAFFAkJOgAIAA8mAA==.Talrip:BAABLgAECn8eAAIiAAkJVR3YBgAgAgAiAAkJVR3YBgAgAgAAAA==.Taxiplease:BAAALgAECggJBwAAAA==.',
Th='Thicctrix:BAAALgADCgcJDAAAAA==.Thornhub:BAAALgAECgUJBQAAAA==.Thundon:BAAALgADCgcJCQAAAA==.',
To='Toatem:BAAALgAECgYJCwAAAA==.Toro:BAACLgAFFH8gAAIcAAgJgxwuAwBYAgAcAAgJgxwuAwBYAgAuAAQKfysAAhwACQl3JGUFAFADABwACQl3JGUFAFADAAAA.',
Tr='Traitor:BAAALgADCgEJAQAAAA==.Trappynomnom:BAAALgAFFAIJAgAAAA==.Tree:BAACLgAFFH8PAAIUAAQJBiSaGACaAQAUAAQJBiSaGACaAQAuAAQKfxYAAhQABgmZI1geAEwCABQABgmZI1geAEwCAAAA.Treegrundler:BAAALgAECgYJEwAAAA==.Treeus:BAAALgAECgYJCQAAAA==.Trixulous:BAAALgADCgkJJQAAAA==.',
Tw='Twiigee:BAABLgAECn8XAAIIAAYJWSANIAABAgAIAAYJWSANIAABAgAAAA==.',
Tz='Tzungxie:BAABLgAECn8tAAIeAAkJWR3pDQBJAgAeAAkJWR3pDQBJAgAAAA==.',
Un='Unholylord:BAACLgAFFH8hAAIaAAgJaSBSAgCPAgAaAAgJaSBSAgCPAgAuAAQKfyIAAhoACQmtI8oEAEcDABoACQmtI8oEAEcDAAAA.',
Va='Vae:BAAALgAECgMJAwAAAA==.Vagbadge:BAAALgAECgkJEgABLgAFFAgJIQAaAGkgAA==.Varroww:BAAALgAECgYJEQAAAA==.',
Vo='Vosxo:BAAALgAECgEJAQAAAA==.',
['Ví']='Vígo:BAABLgAECn9IAAIBAAkJ1gy3AAAyAQABAAkJ1gy3AAAyAQAAAA==.',
Wa='Wado:BAAALgAECgEJAQAAAA==.',
We='Wellíngton:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgAECgEJAQAAAA==.',
Wi='Wicke:BAAALgADCgQJBAABLgAECgEJAgAMAAAAAA==.',
Wo='Wolfthetree:BAAALgAECgUJCAAAAA==.',
Wy='Wystarr:BAAALgADCgIJAgAAAA==.',
Xa='Xamael:BAAALgADCgMJAwAAAA==.',
Xe='Xerkz:BAAALgAECgEJAQAAAA==.',
Ys='Ystarian:BAACLgAFFH8RAAMDAAUJQRQhBAAuAQADAAUJ5hIhBAAuAQACAAMJIA1vRwCrAAAuAAQKf0YABAMACQmbHn0CAJYCAAMACQmbHn0CAJYCAAIACAmMFRwdAN4BAAQAAQkbAfNOACAAAAAA.',
Za='Zaptik:BAAALgAECgEJAgAAAA==.',
['Ël']='Ëlëmëntary:BAAALgAECgcJBgAAAA==.',
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
