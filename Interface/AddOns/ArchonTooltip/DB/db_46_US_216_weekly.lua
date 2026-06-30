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

local lookup = {'Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Druid-Guardian','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Enhancement','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Vengeance',}
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=46,date='2026-06-28',data={Ab='Abeteon:BAAALgAECgEJAQAAAA==.',
Ac='Acinovanth:BAAALgAECgEJAQAAAA==.Acousticjeff:BAAALgAECgYJBgAAAA==.',
Ad='Adwill:BAABLgAECn8vAAIBAAgJ6B8VCgBKAgABAAgJ6B8VCgBKAgAAAA==.',
Ae='Aelvoker:BAACLgAFFH8ZAAQCAAcJuhqEFwCtAQACAAcJsBWEFwCtAQADAAQJPhUNBAAJAQAEAAQJ7gaBEwCQAAAuAAQKfxcABAMACQlFH1EHAHcCAAMABgkkI1EHAHcCAAQABwmdEYkaALcBAAIAAgndGtFKAKkAAAAA.',
Ai='Aindra:BAAALgAECggJEAAAAA==.Airen:BAAALgAECgYJDQAAAA==.',
An='Antidead:BAABLgAECn8gAAMFAAgJOR50BQCfAgAFAAgJOR50BQCfAgAGAAgJ1xM0eAB+AQAAAA==.',
Ap='Apachaler:BAABLgAECn8nAAQHAAkJ+xocEQCZAgAHAAkJ+xocEQCZAgAIAAEJNhk/hQBCAAAJAAEJIgkvpAAsAAAAAA==.',
Ar='Arathael:BAAALgADCgIJAgAAAA==.Ardyce:BAAALgADCgIJAgAAAA==.Arrae:BAAALgAECgUJAwAAAA==.Arreuws:BAAALgAECgQJBAAAAA==.',
As='Asiansmoliv:BAACLgAFFH8VAAMKAAQJSB+HAwBeAQAKAAQJSB+HAwBeAQALAAIJ5x5lMgCuAAAuAAQKfzQAAwoACQkgJWkAAFEDAAoACQkgJWkAAFEDAAsABQm6HydVAJ0BAAAA.',
Az='Azriel:BAAALgADCgMJBAAAAA==.Azshan:BAAALgADCgQJBAABLgAECgQJCwAMAAAAAA==.',
Ba='Babymager:BAABLgAECn8iAAINAAcJ5QtUuQATAQANAAcJ5QtUuQATAQAAAA==.Babyshamz:BAAALgAECgYJBgAAAA==.Barranphalnx:BAAALgAECgMJBQAAAA==.',
Bb='Bbldrizzy:BAAALgADCgEJAQAAAA==.',
Be='Beartwige:BAAALgADCgYJBgAAAA==.Beefydomo:BAAALgADCgIJAgABLgAECgEJAQAMAAAAAA==.Belladonnà:BAAALgAECgYJDQABLgAECgkJIgAOAH8RAA==.Betsy:BAAALgAECgQJBAAAAA==.',
Bh='Bhal:BAAALgAECgEJAQAAAA==.',
Bi='Bigpopapump:BAACLgAFFH8WAAIPAAQJxR0bDgBUAQAPAAQJxR0bDgBUAQAuAAQKfzwAAg8ACQnRJRQBAGADAA8ACQnRJRQBAGADAAAA.Bishop:BAAALgADCgMJAwAAAA==.',
Bl='Blackgarden:BAAALgAECgYJDgAAAA==.Bloodhorde:BAAALgAECgEJAQAAAA==.Bloodydak:BAEALgAECgcJBwABLgAECgcJEAAMAAAAAA==.Bluchu:BAEALgAECgEJAQABLgAECgcJEAAMAAAAAA==.',
Bo='Bombasharna:BAAALgAECgIJBAAAAA==.Bonkzx:BAAALgADCgMJAwAAAA==.Booze:BAAALgAECgkJDwAAAA==.',
Br='Brigne:BAAALgADCgYJCwAAAA==.',
Bu='Buddeez:BAACLgAFFH8dAAINAAgJzB3XDwBtAgANAAgJzB3XDwBtAgAuAAQKfysAAg0ACQk/JU0KAHEDAA0ACQk/JU0KAHEDAAAA.Buddiez:BAAALgADCgEJAQAAAA==.Built:BAABLgAECn8eAAQPAAkJ9CBYDAAJAgAPAAgJASFYDAAJAgAQAAMJTBi+fwDoAAARAAEJ2hhogQBBAAAAAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Carrot:BAAALgAECgIJAgAAAA==.',
Ce='Cenwen:BAACLgAFFH8VAAINAAQJYBosSwBKAQANAAQJYBosSwBKAQAuAAQKfycAAg0ACQmVHmdCABQCAA0ACQmVHmdCABQCAAAA.',
Ch='Chaos:BAACLgAFFH8FAAIPAAMJhxpcHADuAAAPAAMJhxpcHADuAAAuAAQKf08AAg8ACQluJegAAGgDAA8ACQluJegAAGgDAAAA.Chonk:BAAALgAECgYJBgAAAA==.Chugginjizz:BAAALgAECgEJAQABLgAFFAgJJgASADEWAA==.',
Cl='Clawreece:BAAALgAECgQJCQAAAA==.',
Co='Conta:BAAALgAECgYJCQAAAA==.',
Cr='Cryingtears:BAABLgAECn8pAAQTAAgJ9A8gOgBiAQATAAgJ9A8gOgBiAQAGAAcJqQYK6QDTAAAFAAEJAAE8WwAYAAAAAA==.',
Cu='Cuchicu:BAABLgAECn9EAAMUAAkJLxytDwDVAgAUAAkJLxytDwDVAgAVAAUJnhNaOgApAQAAAA==.',
Da='Dakkonix:BAEALgAECgcJEAAAAA==.Dakkonixx:BAEALgAECgUJBgABLgAECgcJEAAMAAAAAA==.Damagexx:BAAALgAECgMJBgAAAA==.Darkaged:BAAALgADCgYJBgAAAA==.Darklords:BAAALgAECgMJAwAAAA==.Daviid:BAAALgADCgYJBgAAAA==.',
De='Demigodd:BAAALgADCgIJAgAAAA==.Demonasa:BAAALgADCgIJAgAAAA==.Desim:BAABLgAECn8WAAISAAcJsx6EMwBoAgASAAcJsx6EMwBoAgAAAA==.Dextt:BAABLgAECn8dAAIWAAcJLCIrDgCpAgAWAAcJLCIrDgCpAgAAAA==.Dez:BAACLgAFFH8IAAITAAMJAQsuDQCcAAATAAMJAQsuDQCcAAAuAAQKfyYAAhMACQnJFcQZADgCABMACQnJFcQZADgCAAAA.',
Dk='Dkamp:BAAALgADCgkJGQAAAA==.',
Dm='Dmoney:BAAALgAECgYJBgAAAA==.',
Do='Dondiablo:BAAALgAECgYJDQAAAA==.Doylock:BAAALgAECgUJBQAAAA==.',
Dr='Dragnaballs:BAEALgAECgcJEgABLgAFFAkJUAANACwkAA==.Drdot:BAAALgAECgEJBQABLgAECggJHwASALsaAA==.Drehd:BAACLgAFFH8KAAIWAAMJvCQvMQAdAQAWAAMJvCQvMQAdAQAuAAQKfy0AAhYACAnVJFwJAB0DABYACAnVJFwJAB0DAAAA.Drewbear:BAAALgAFFAEJAQABLgAFFAQJDQAXADEbAA==.Drewcifer:BAACLgAFFH8NAAIXAAQJMRuAFAD8AAAXAAQJMRuAFAD8AAAuAAQKfy0AAhcACQlFIt0LAOgCABcACQlFIt0LAOgCAAEuAAUUBAkNABcAMRsA.Drewwar:BAAALgAECgEJAQABLgAFFAQJDQAXADEbAA==.Dripps:BAAALgAECgYJBgAAAA==.',
Du='Dumalshadows:BAAALgAECgUJBQAAAA==.Dumper:BAAALgADCgEJAQAAAA==.Dumps:BAAALgAECgMJAwAAAA==.',
['Dó']='Dóom:BAAALgAECgUJCQABLgAFFAMJAwAMAAAAAA==.',
['Dü']='Düsk:BAAALgADCgUJBQABLgAECgMJCgAMAAAAAA==.',
Eg='Egoon:BAAALgAECgQJBgAAAA==.',
El='Elarial:BAAALgADCgEJAQAAAA==.Elmerfud:BAAALgAECgYJBwAAAA==.',
En='Enrèk:BAAALgADCgYJBgAAAA==.',
Fa='Falafel:BAACLgAFFH8lAAISAAcJNB+oIQDqAQASAAcJNB+oIQDqAQAuAAQKfygAAhIACQlOIuwSAAoDABIACQlOIuwSAAoDAAAA.',
Fi='Fidely:BAAALgADCgEJAQAAAA==.',
Fl='Flop:BAAALgADCgIJAgAAAA==.',
Fo='Fomo:BAAALgADCgYJBgAAAA==.Fornax:BAAALgAECgQJBwABLgAECgcJFwANAA8MAA==.Fotmtrash:BAACLgAFFH8XAAQYAAQJYR5aFgANAQAZAAQJTBdRJgAYAQAYAAMJbCBaFgANAQAaAAIJ4gQfNAByAAAuAAQKfzQABBkACQk4I/gFACUDABkACQn+H/gFACUDABgACAkZIu8HAMwCABoAAgknCWFaAE4AAAAA.Foxxydots:BAABLgAECn82AAILAAkJ5RjxMAAVAgALAAkJ5RjxMAAVAgAAAA==.',
Fr='Frostitoot:BAABLgAECn8XAAINAAcJDwwStwAXAQANAAcJDwwStwAXAQAAAA==.',
Fu='Fupa:BAAALgAECgEJAQAAAA==.',
Ga='Galbsadi:BAABLgAECn8rAAMbAAgJnRTUEgAeAQALAAgJNhLCcgBUAQAbAAcJtQ/UEgAeAQAAAA==.Garrius:BAAALgADCgQJBAAAAA==.',
Ge='Gelfdar:BAAALgAECgEJAQAAAA==.Genie:BAAALgAECgEJAQAAAA==.Gethendriel:BAAALgAECgUJDAAAAA==.Getsuga:BAABLgAECn8UAAMWAAkJ7xy2AADzAgAWAAkJ7xy2AADzAgAcAAgJxRhqAAA0AgAAAA==.',
Gh='Ghostmonk:BAABLgAFFH8JAAIJAAMJgA4qBwDIAAAJAAMJgA4qBwDIAAABLgAFFAcJMwASAP8dAA==.',
Gl='Glaia:BAAALgADCgYJDQAAAA==.',
Go='Goel:BAAALgAECgEJAgAAAA==.',
Gr='Graf:BAABLgAECn8mAAQdAAkJhSHcHABnAgAdAAcJQyLcHABnAgABAAYJPRgFGwAZAQAeAAYJshoPMQC6AAAAAA==.Grafbear:BAAALgADCgQJBAAAAA==.Graflock:BAAALgAECgUJBQAAAA==.Grimzorath:BAAALgAECgYJBgAAAA==.Grox:BAABLgAECn8UAAIdAAYJmg+qTgBsAQAdAAYJmg+qTgBsAQAAAA==.Grudge:BAAALgADCgMJBQAAAA==.',
Gu='Gulpan:BAAALgAFFAEJAQAAAA==.',
Ha='Hackensack:BAAALgAECggJEAAAAA==.Hamtaro:BAAALgAECgYJDAAAAA==.Hawthorne:BAACLgAFFH8HAAIHAAQJygjlEgCCAAAHAAQJygjlEgCCAAAuAAQKfyMAAgcACQmkHZIUAHYCAAcACQmkHZIUAHYCAAAA.',
Hi='Hiyabusa:BAABLgAECn8UAAIfAAcJ4BBDLQCWAQAfAAcJ4BBDLQCWAQAAAA==.',
Ho='Hollowboi:BAABLgAECn88AAIIAAkJMiIKBAAJAwAIAAkJMiIKBAAJAwAAAA==.Holygraf:BAAALgAECgcJDgAAAA==.',
Ia='Iamyama:BAAALgAECgUJCQAAAA==.',
Il='Illgaz:BAAALgAECgEJAQAAAA==.',
Io='Ionna:BAAALgADCgcJBwABLgAECgkJFAAWAO8cAA==.',
Jd='Jdvance:BAAALgAECgYJBgAAAA==.',
Jh='Jhouska:BAAALgAECgcJEAAAAA==.',
Jo='Jormunngandr:BAACLgAFFH8mAAQSAAgJMRZrGAAdAgASAAcJMRZrGAAdAgAgAAEJ4AYhDgBKAAAhAAEJAAA4FQBGAAAuAAQKfx8AAhIACQm9IK0RABIDABIACQm9IK0RABIDAAAA.',
Ju='Judgynomnom:BAACLgAFFH8KAAITAAQJmhn6IwABAQATAAQJmhn6IwABAQAuAAQKfxwAAhMACAloJtwJANQCABMACAloJtwJANQCAAAA.',
Jy='Jyggles:BAABLgAECn8pAAIhAAgJEALUBQCMAAAhAAgJEALUBQCMAAAAAA==.',
Ka='Kavdh:BAACLgAFFH8PAAIXAAYJ7xyNCACYAQAXAAYJ7xyNCACYAQAuAAQKfywAAhcACQk8JIgDAE8DABcACQk8JIgDAE8DAAAA.',
Ke='Kenpachip:BAAALgAECgUJBQAAAA==.Keyaesh:BAAALgAECgEJAQAAAA==.',
Ki='Kirax:BAAALgAECgEJAQAAAA==.',
Ko='Konataizumi:BAAALgADCgcJCwAAAA==.',
Kr='Kruhks:BAAALgAECgYJCAABLgAFFAMJCgAWALwkAA==.',
Ks='Kshot:BAABLgAECn89AAIPAAkJmR+OBgC4AgAPAAkJmR+OBgC4AgAAAA==.',
La='Lagdalen:BAABLgAECn8aAAIYAAYJExxBHwDKAQAYAAYJExxBHwDKAQAAAA==.Lanachan:BAABLgAECn9IAAIdAAkJ7RgdEwBZAgAdAAkJ7RgdEwBZAgAAAA==.',
Ld='Ldn:BAABLgAECn9GAAINAAkJBxULBgB0AQANAAkJBxULBgB0AQAAAA==.',
Le='Lep:BAAALgAECgUJBQAAAA==.',
Li='Lightofdawn:BAAALgAECgEJAQAAAA==.Likai:BAAALgADCgUJBQAAAA==.Lisa:BAAALgADCgcJAQAAAA==.Liz:BAACLgAFFH8IAAIQAAMJRgU8HgDGAAAQAAMJRgU8HgDGAAAuAAQKfzsAAhAACQm8Cq9dAI0BABAACQm8Cq9dAI0BAAAA.',
Ly='Lylieth:BAABLgAECn87AAILAAkJyBOBPgDiAQALAAkJyBOBPgDiAQAAAA==.Lyndyn:BAAALgADCgIJAgAAAA==.',
Ma='Mather:BAAALgAECgEJAgAAAA==.Mayzel:BAAALgAECgMJBAAAAA==.',
Mi='Microsqueeze:BAAALgADCgkJCQAAAA==.Miriko:BAAALgADCgkJCQAAAA==.',
Mo='Mock:BAACLgAFFH8IAAICAAMJaQKYUgB/AAACAAMJaQKYUgB/AAAuAAQKfyIAAgIACQntDvoDAOsAAAIACQntDvoDAOsAAAEuAAQKCQkjABkAqgwA.Mogera:BAAALgADCgMJBQAAAA==.Mouthyhusky:BAABLgAFFH8GAAIQAAQJDgObXwDlAAAQAAQJDgObXwDlAAAAAA==.',
Ni='Ninluv:BAAALgAECgQJDgAAAA==.',
Ny='Nyancat:BAAALgAECgEJAQAAAA==.',
Ol='Olaho:BAAALgADCgYJBgAAAA==.',
Om='Omenz:BAAALgADCgIJAgAAAA==.Omey:BAAALgAECgEJBAAAAA==.',
Oo='Oojni:BAAALgADCgYJBgAAAA==.',
Or='Oraine:BAAALgAECgUJBQAAAA==.Ortrazzarn:BAAALgAECgEJAQABLgAECgkJPAAIADIiAA==.',
Pa='Pazzman:BAAALgADCgYJBwAAAA==.',
Pe='Perc:BAAALgAECgQJBAAAAA==.',
Ph='Pharhar:BAABLgAECn81AAMTAAkJWiEoEACXAgATAAkJWiEoEACXAgAGAAUJHRskpgAuAQAAAA==.',
Po='Poppachàdson:BAABLgAECn8dAAIcAAcJ+CDTCABPAgAcAAcJ+CDTCABPAgABLgAFFAMJBgAcABoVAA==.Poppadadson:BAACLgAFFH8GAAIcAAMJGhXuDwDHAAAcAAMJGhXuDwDHAAAuAAQKfxwAAhwABwmBH4kGAI0CABwABwmBH4kGAI0CAAAA.Poppadotson:BAAALgAECgMJAwABLgAFFAMJBgAcABoVAA==.',
Pr='Priceisright:BAAALgADCgUJBQAAAA==.Priceless:BAAALgAECgkJDAAAAA==.',
Pu='Puscifer:BAAALgAECgkJCQAAAA==.',
Qu='Quarrior:BAAALgADCgEJAQABLgAECgMJCgAMAAAAAA==.Quellazaire:BAAALgADCgcJDAAAAA==.Quincar:BAAALgADCgEJAQABLgAECgMJCgAMAAAAAA==.',
Ra='Rafayel:BAAALgAECgMJAwABLgAECgkJRAAUAC8cAA==.Raizel:BAAALgAECgYJBwABLgAECgkJRAAUAC8cAA==.Ravister:BAAALgAECgUJBQABLgAFFAgJIQAaAGkgAA==.',
Re='Rebecknight:BAAALgAECgQJBAABLgAECgkJPAAIADIiAA==.Relic:BAACLgAFFH8jAAQgAAcJFBJ0BAC7AQAgAAYJ1RF0BAC7AQASAAEJnBEEFQE+AAAhAAIJxQv9QgAoAAAuAAQKfykAAyAACQmEHZMCAIwCACAACQmEHZMCAIwCABIABgmbF4eCAF4BAAAA.Renk:BAABLgAECn8vAAISAAkJACYPBQBUAwASAAkJACYPBQBUAwAAAA==.Renka:BAAALgAECgUJBQABLgAECgkJLwASAAAmAA==.',
Ro='Ronald:BAABLgAECn8UAAIGAAYJZRrhlgBPAQAGAAYJZRrhlgBPAQAAAA==.Rowdyrebel:BAAALgAECgkJDAAAAA==.Roykevious:BAAALgAECgEJAwAAAA==.',
Sa='Saeyl:BAAALgAECgYJDAABLgAECgkJIAAZAB0KAA==.Saihu:BAAALgADCgEJAQABLgAECgkJFAAWAO8cAA==.Sammie:BAEALgAECgUJCAABLgAECgcJEAAMAAAAAA==.Sarix:BAAALgAECgQJBAAAAA==.Sarromand:BAAALgAECgUJBQABLgAECgkJPAAIADIiAA==.Savant:BAAALgAECgMJAwAAAA==.Sayl:BAABLgAECn8gAAMZAAkJHQpyNwA1AQAZAAgJjAlyNwA1AQAaAAUJMwgeWQCwAAAAAA==.',
Sc='Scallywinkle:BAAALgAECgcJEAAAAA==.Scrap:BAABLgAECn8aAAMLAAkJ4hqLPgATAgALAAgJcBqLPgATAgAbAAQJeRTgKwAQAQAAAA==.',
Se='Senova:BAAALgAECgIJAgAAAA==.',
Sh='Shadowghoul:BAABLgAECn8WAAIaAAgJbwrUNgA6AQAaAAgJbwrUNgA6AQAAAA==.Shadowydern:BAABLgAECn8oAAMaAAkJlSACCgCuAgAaAAkJlSACCgCuAgAYAAEJ/RBpfwAzAAAAAA==.Shamewow:BAACLgAFFH8aAAIWAAcJ8RU9EwDNAQAWAAcJ8RU9EwDNAQAuAAQKfzMAAhYACQlIHNcWAJMCABYACQlIHNcWAJMCAAAA.Sharkbite:BAAALgAECgQJCwAAAA==.Shrimpboat:BAAALgAECgYJBQAAAA==.',
Si='Sicknnasty:BAACLgAFFH8dAAIhAAYJmBUFEgBqAQAhAAYJmBUFEgBqAQAuAAQKf0oAAyEACQkMIuMHAJoCACEACQkMIuMHAJoCABIACAlRFqpaALYBAAAA.Sicsickly:BAAALgAFFAEJAQAAAA==.',
Sl='Slayerz:BAAALgAECgYJBgAAAA==.',
Sn='Snattch:BAAALgAECgQJBwAAAA==.Snookismalls:BAABLgAECn8jAAMZAAkJqgx7IQDCAQAZAAkJqgx7IQDCAQAaAAcJXwdiRgD2AAAAAA==.',
So='Solarian:BAAALgADCgMJAwAAAA==.Solitary:BAABLgAECn8fAAISAAgJuxrxMAA7AgASAAgJuxrxMAA7AgAAAA==.Sos:BAAALgAECgEJAgAAAA==.',
Sp='Sparkyboo:BAAALgAECgEJAQAAAA==.Speed:BAAALgAECgYJCwAAAA==.Spinach:BAAALgAECgMJAQABLgAECgYJBQAMAAAAAA==.',
St='Starshopping:BAABLgAECn8aAAIXAAgJmiHoAgCPAQAXAAgJmiHoAgCPAQABLgAFFAMJBQAPAIcaAA==.',
Su='Sunari:BAAALgADCgQJBAAAAA==.',
Ta='Taewryn:BAABLgAFFH8FAAMeAAQJQA/ZGgDAAAAeAAQJQA/ZGgDAAAAdAAEJYgWYVwA7AAABLgAFFAkJQgAIAFcmAA==.Talrip:BAABLgAECn8eAAIiAAkJVR3YBgAgAgAiAAkJVR3YBgAgAgAAAA==.Taxiplease:BAAALgAECggJBwAAAA==.',
Th='Thicctrix:BAAALgADCgcJDAAAAA==.Thornhub:BAAALgAECgUJBQAAAA==.Thundon:BAAALgADCgcJCQAAAA==.',
To='Toatem:BAAALgAECgYJCwAAAA==.Toro:BAACLgAFFH8gAAIdAAgJgxwuAwBYAgAdAAgJgxwuAwBYAgAuAAQKfysAAh0ACQl3JGUFAFADAB0ACQl3JGUFAFADAAAA.',
Tr='Traitor:BAAALgADCgEJAQAAAA==.Trappynomnom:BAAALgAFFAIJAgAAAA==.Tree:BAACLgAFFH8PAAIUAAQJBiSYGACaAQAUAAQJBiSYGACaAQAuAAQKfxYAAhQABgmZI1geAEwCABQABgmZI1geAEwCAAAA.Treegrundler:BAAALgAECgYJEwAAAA==.Treeus:BAAALgAECgYJCQAAAA==.Trixulous:BAAALgADCgkJJQAAAA==.',
Tw='Twiigee:BAABLgAECn8XAAIIAAYJWSANIAABAgAIAAYJWSANIAABAgAAAA==.',
Tz='Tzungxie:BAABLgAECn8tAAIfAAkJWR3rDQBJAgAfAAkJWR3rDQBJAgAAAA==.',
Ud='Udungoofedd:BAAALgADCgYJBgAAAA==.',
Un='Unholylord:BAACLgAFFH8hAAIaAAgJaSBSAgCPAgAaAAgJaSBSAgCPAgAuAAQKfyIAAhoACQmtI8oEAEcDABoACQmtI8oEAEcDAAAA.',
Va='Vae:BAAALgAECgMJAwAAAA==.Vagbadge:BAAALgAECgkJEgABLgAFFAgJIQAaAGkgAA==.Varroww:BAAALgAECgYJEQAAAA==.',
Vo='Vosxo:BAAALgAECgEJAQAAAA==.',
['Ví']='Vígo:BAABLgAECn9KAAIBAAkJWQ1kAQBcAQABAAkJWQ1kAQBcAQAAAA==.',
Wa='Wado:BAAALgAECgEJAQAAAA==.',
We='Wellíngton:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgAECgEJAQAAAA==.',
Wi='Wicke:BAAALgADCgQJBAABLgAECgEJAgAMAAAAAA==.',
Wo='Wolfthetree:BAAALgAECgUJCAAAAA==.',
Wy='Wystarr:BAAALgADCgIJAgAAAA==.',
Xa='Xamael:BAAALgADCgMJAwAAAA==.',
Xe='Xerkz:BAAALgAECgEJAQAAAA==.',
Ys='Ystarian:BAACLgAFFH8RAAMDAAUJQRQgBAAuAQADAAUJ5hIgBAAuAQACAAMJIA11RwCrAAAuAAQKf0YABAMACQmbHn0CAJYCAAMACQmbHn0CAJYCAAIACAmMFRwdAN4BAAQAAQkbAfNOACAAAAAA.',
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
