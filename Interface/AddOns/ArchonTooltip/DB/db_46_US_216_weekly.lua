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

local lookup = {'Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Hunter-Survival','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Priest-Shadow','Warlock-Destruction','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Frost','DemonHunter-Vengeance',}
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=46,date='2026-05-17',data={Ac='Acinovanth:BAAALgAECgEJAQAAAA==.Acousticjeff:BAAALgAECgYJBgAAAA==.',
Ad='Adwill:BAABLgAECn8mAAIBAAgJ3B9xBgBTAgABAAgJ3B9xBgBTAgAAAA==.',
Ae='Aelvoker:BAACLgAFFH8XAAQCAAYJvR2wDACdAQACAAYJshewDACdAQADAAQJPhUNBAAJAQAEAAQJ7gaBEwCQAAAuAAQKfxcABAMACQlFH1EHAHcCAAMABgkkI1EHAHcCAAQABwmdEYkaALcBAAIAAgndGtFKAKkAAAAA.',
Ai='Aindra:BAAALgAECggJEAAAAA==.Airen:BAAALgAECgQJBQAAAA==.',
An='Antidead:BAABLgAECn8gAAMFAAgJOR50BQCfAgAFAAgJOR50BQCfAgAGAAgJ1xP/UQCXAQAAAA==.',
Ap='Apachaler:BAABLgAECn8jAAMHAAgJ1RwBDgBmAgAHAAgJ1RwBDgBmAgAIAAEJNhm9bQBEAAAAAA==.',
Ar='Arathael:BAAALgADCgIJAgAAAA==.Ardyce:BAAALgADCgIJAgAAAA==.Arrae:BAAALgAECgUJAwAAAA==.Arreuws:BAAALgAECgQJBAAAAA==.',
As='Asiansmoliv:BAACLgAFFH8OAAMJAAMJwyCwAgAcAQAJAAMJwyCwAgAcAQAKAAIJ9htlMgCuAAAuAAQKfzAAAwkACQn8JB8AAGcDAAkACQn8JB8AAGcDAAoABQm6H+w8ALQBAAAA.',
Ba='Babymager:BAABLgAECn8eAAILAAcJ1wv9jQAqAQALAAcJ1wv9jQAqAQAAAA==.Babyshamz:BAAALgAECgYJBgAAAA==.',
Be='Beartwige:BAAALgADCgYJBgAAAA==.Belladonnà:BAAALgADCgQJBAAAAA==.Betsy:BAAALgAECgQJBAAAAA==.',
Bi='Bigpopapump:BAACLgAFFH8RAAIMAAQJThlYCABeAQAMAAQJThlYCABeAQAuAAQKfzsAAgwACAm1JrcBABYDAAwACAm1JrcBABYDAAAA.Bishop:BAAALgADCgMJAwAAAA==.',
Bl='Blackgarden:BAAALgAECgUJBwAAAA==.Bloodydak:BAEALgAECgcJBwABLgAECgcJEAANAAAAAA==.',
Bo='Bombasharna:BAAALgADCgMJBQAAAA==.Bonkzx:BAAALgADCgMJAwAAAA==.Booze:BAAALgAECgkJDwAAAA==.',
Br='Brigne:BAAALgADCgYJCwAAAA==.',
Bu='Buddeez:BAACLgAFFH8YAAILAAUJBB5HEwB/AQALAAUJBB5HEwB/AQAuAAQKfysAAgsACQk/JU0KAHEDAAsACQk/JU0KAHEDAAAA.Built:BAABLgAECn8eAAQMAAkJ9CBYDAAJAgAMAAgJASFYDAAJAgAOAAMJTBi+fwDoAAAPAAEJ2hhogQBBAAAAAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Carrot:BAAALgAECgIJAgAAAA==.',
Ce='Cenwen:BAACLgAFFH8IAAILAAMJ4wxuXQDtAAALAAMJ4wxuXQDtAAAuAAQKfyUAAgsACAmVHMxfABwCAAsACAmVHMxfABwCAAAA.',
Ch='Chaos:BAABLgAECn8wAAIMAAkJ9yHWAgDrAgAMAAkJ9yHWAgDrAgAAAA==.Chonk:BAAALgAECgYJBgAAAA==.Chugginjizz:BAAALgAECgEJAQABLgAFFAcJHwAQAFEVAA==.',
Cl='Clawreece:BAAALgAECgQJBgAAAA==.',
Co='Conta:BAAALgAECgYJCQAAAA==.',
Cr='Cryingtears:BAABLgAECn8kAAQRAAgJgw3JSwBJAQARAAgJgw3JSwBJAQAGAAcJqQZZqQDrAAAFAAEJAAENRQAZAAAAAA==.',
Cu='Cuchicu:BAABLgAECn88AAMSAAkJ1hubCgDeAgASAAkJ1hubCgDeAgATAAEJKwm3dQAnAAAAAA==.',
Da='Dakkonix:BAEALgAECgcJEAAAAA==.Dakkonixx:BAEALgAECgUJBQABLgAECgcJEAANAAAAAA==.Damagexx:BAAALgAECgEJAQAAAA==.Darkaged:BAAALgADCgYJBgAAAA==.Darklords:BAAALgADCgEJAQAAAA==.Daviid:BAAALgADCgYJBgAAAA==.',
De='Demigodd:BAAALgADCgIJAgAAAA==.Demonasa:BAAALgADCgIJAgAAAA==.Desim:BAABLgAECn8WAAIQAAcJsx6EMwBoAgAQAAcJsx6EMwBoAgAAAA==.Dextt:BAABLgAECn8dAAIUAAcJLCIrDgCpAgAUAAcJLCIrDgCpAgAAAA==.Dez:BAABLgAECn8dAAIRAAgJDhSjHgDNAQARAAgJDhSjHgDNAQAAAA==.',
Dk='Dkamp:BAAALgADCgQJDAAAAA==.',
Dm='Dmoney:BAAALgAECgYJBgAAAA==.',
Do='Dondiablo:BAAALgAECgYJDQAAAA==.Doylock:BAAALgAECgUJBQAAAA==.',
Dr='Dragnaballs:BAAALgAECgcJEgABLgAFFAgJJAALANAWAA==.Drehd:BAACLgAFFH8KAAIUAAMJvCT9GQA0AQAUAAMJvCT9GQA0AQAuAAQKfy0AAhQACAnWJKMEACwDABQACAnWJKMEACwDAAAA.Drewcifer:BAABLgAECn8kAAIVAAkJfR+BFgDPAgAVAAkJfR+BFgDPAgABLgAECgkJJAAVAH0fAA==.Drewwar:BAAALgAECgEJAQABLgAECgkJJAAVAH0fAA==.Dripps:BAAALgAECgYJBgAAAA==.',
Du='Dumper:BAAALgADCgEJAQAAAA==.Dumps:BAAALgAECgMJAwAAAA==.',
['Dó']='Dóom:BAAALgAECgUJCQABLgAFFAMJAwANAAAAAA==.',
['Dü']='Düsk:BAAALgADCgUJBQABLgAECgEJBAANAAAAAA==.',
Eg='Egoon:BAAALgAECgQJBgAAAA==.',
El='Elmerfud:BAAALgAECgYJBwAAAA==.',
En='Enrèk:BAAALgADCgYJBgAAAA==.',
Fa='Falafel:BAACLgAFFH8SAAIQAAUJkx/OKgBiAQAQAAUJkx/OKgBiAQAuAAQKfygAAhAACQlNIuwSAAoDABAACQlNIuwSAAoDAAAA.',
Fi='Fidely:BAAALgADCgEJAQAAAA==.',
Fo='Fomo:BAAALgADCgYJBgAAAA==.Fornax:BAAALgAECgQJBwABLgAECgcJFwALAA8MAA==.Fotmtrash:BAACLgAFFH8NAAMWAAQJVhrWFQA8AQAWAAQJkxbWFQA8AQAXAAMJvBQ5DACeAAAuAAQKfy4ABBcACAnXI+8HAMwCABYACAk1IGcGANsCABcACAkaIu8HAMwCABgAAgknCWFaAE4AAAAA.Foxxydots:BAABLgAECn8vAAIKAAkJfhhpJQAWAgAKAAkJfhhpJQAWAgAAAA==.',
Fr='Frostitoot:BAABLgAECn8XAAILAAcJDwxUjAAsAQALAAcJDwxUjAAsAQAAAA==.',
Ga='Galbsadi:BAABLgAECn8kAAMZAAgJ8hKUDQAhAQAKAAgJzA4YWgBfAQAZAAcJtQ+UDQAhAQAAAA==.Garrius:BAAALgADCgQJBAAAAA==.',
Ge='Gelfdar:BAAALgAECgEJAQAAAA==.Gethendriel:BAAALgAECgQJCQAAAA==.',
Gl='Glaia:BAAALgADCgYJDQAAAA==.',
Go='Goel:BAAALgAECgEJAgAAAA==.',
Gr='Graf:BAABLgAECn8kAAQaAAkJviDcHABnAgAaAAcJOiHcHABnAgABAAYJPRgFGwAZAQAbAAYJshofJgDDAAAAAA==.Graflock:BAAALgAECgEJAQAAAA==.Grimzorath:BAAALgAECgYJBgAAAA==.Grox:BAABLgAECn8UAAIaAAYJmg+qTgBsAQAaAAYJmg+qTgBsAQAAAA==.Grudge:BAAALgADCgMJBQAAAA==.',
Ha='Hackensack:BAAALgAECggJEAAAAA==.Hamtaro:BAAALgAECgMJBAAAAA==.Hawthorne:BAABLgAECn8aAAIHAAcJ7x3cFAAgAgAHAAcJ7x3cFAAgAgAAAA==.',
Hi='Hiyabusa:BAABLgAECn8UAAIcAAcJ4BBDLQCWAQAcAAcJ4BBDLQCWAQAAAA==.',
Ho='Hollowboi:BAABLgAECn8xAAIIAAgJhR8ECgBiAgAIAAgJhR8ECgBiAgAAAA==.Holygraf:BAAALgAECgcJDgAAAA==.',
Ia='Iamyama:BAAALgAECgUJCQAAAA==.',
Il='Illgaz:BAAALgAECgEJAQAAAA==.',
Io='Ionna:BAAALgADCgcJBwAAAA==.',
Jd='Jdvance:BAAALgAECgYJBgAAAA==.',
Jh='Jhouska:BAAALgAECgcJEAAAAA==.',
Jo='Jormunngandr:BAACLgAFFH8fAAMQAAcJURX1CQD6AQAQAAYJURX1CQD6AQAdAAEJAAA4FQBGAAAuAAQKfx8AAhAACQm9IK0RABIDABAACQm9IK0RABIDAAAA.',
Ju='Judgynomnom:BAACLgAFFH8GAAIRAAQJ8xZZFgArAQARAAQJ8xZZFgArAQAuAAQKfxwAAhEACAloJtwJANQCABEACAloJtwJANQCAAAA.',
Jy='Jyggles:BAAALgAECgYJDgAAAA==.',
Ke='Keyaesh:BAAALgADCgcJCAAAAA==.',
Ki='Kirax:BAAALgADCgEJAQAAAA==.',
Ko='Konataizumi:BAAALgADCgcJCwAAAA==.',
Kr='Kruhks:BAAALgAECgYJCAABLgAFFAMJCgAUALwkAA==.',
Ks='Kshot:BAABLgAECn81AAIMAAkJmR+sBAC1AgAMAAkJmR+sBAC1AgAAAA==.',
La='Lagdalen:BAABLgAECn8aAAIXAAYJExzZFQDkAQAXAAYJExzZFQDkAQAAAA==.Lanachan:BAABLgAECn8tAAIaAAgJthK9IACqAQAaAAgJthK9IACqAQAAAA==.',
Ld='Ldn:BAABLgAECn8wAAILAAkJzA9QRADWAQALAAkJzA9QRADWAQAAAA==.',
Le='Lep:BAAALgAECgUJBQAAAA==.',
Li='Likai:BAAALgADCgUJBQAAAA==.Lisa:BAAALgADCgcJAQAAAA==.Liz:BAABLgAECn8nAAIOAAgJqAk+UgBiAQAOAAgJqAk+UgBiAQAAAA==.',
Ly='Lylieth:BAABLgAECn8yAAIKAAkJlhIgMADkAQAKAAkJlhIgMADkAQAAAA==.Lyndyn:BAAALgADCgIJAgAAAA==.',
Ma='Mather:BAAALgAECgEJAgAAAA==.Mayzel:BAAALgAECgMJBAAAAA==.',
Mi='Microsqueeze:BAAALgADCgkJCQAAAA==.',
Mo='Mock:BAAALgAECgcJDgABLgAECgcJEAANAAAAAA==.Mogera:BAAALgADCgMJBQAAAA==.',
Ni='Ninluv:BAAALgAECgQJDgAAAA==.',
Ny='Nyancat:BAAALgADCgkJCwAAAA==.',
Ol='Olaho:BAAALgADCgYJBgAAAA==.',
Om='Omenz:BAAALgADCgIJAgAAAA==.',
Oo='Oojni:BAAALgADCgYJBgAAAA==.',
Pa='Pazzman:BAAALgADCgYJBwAAAA==.',
Pe='Perc:BAAALgAECgQJBAAAAA==.',
Ph='Pharhar:BAABLgAECn8qAAMRAAgJTCCYFAAoAgARAAgJTCCYFAAoAgAGAAMJihREyAC6AAAAAA==.',
Po='Poppachàdson:BAABLgAECn8dAAIeAAcJ+CDTCABPAgAeAAcJ+CDTCABPAgABLgAFFAMJBgAeABoVAA==.Poppadadson:BAACLgAFFH8GAAIeAAMJGhX+BgDoAAAeAAMJGhX+BgDoAAAuAAQKfxwAAh4ABwmBH4kGAI0CAB4ABwmBH4kGAI0CAAAA.Poppadotson:BAAALgAECgMJAwABLgAFFAMJBgAeABoVAA==.',
Pu='Puscifer:BAAALgAECgkJCAAAAA==.',
Qu='Quarrior:BAAALgADCgEJAQABLgAECgEJBAANAAAAAA==.Quellazaire:BAAALgADCgcJDAAAAA==.Quincar:BAAALgADCgEJAQABLgAECgEJBAANAAAAAA==.',
Ra='Ravister:BAAALgAECgUJBQABLgAFFAUJFAAYAGgjAA==.',
Re='Relic:BAACLgAFFH8WAAMfAAUJRxYjBQA5AQAfAAQJRxYjBQA5AQAdAAIJxQuzKAA3AAAuAAQKfyMAAh8ACQmEHZMCAIwCAB8ACQmEHZMCAIwCAAAA.Renk:BAABLgAECn8pAAIQAAgJ1iRlDgDFAgAQAAgJ1iRlDgDFAgAAAA==.Renka:BAAALgAECgQJBAAAAA==.',
Ro='Ronald:BAABLgAECn8UAAIGAAYJZRrhlgBPAQAGAAYJZRrhlgBPAQAAAA==.Roykevious:BAAALgAECgEJAwAAAA==.',
Sa='Saeyl:BAAALgAECgYJDAABLgAECgkJFwAWAJsJAA==.Sammie:BAEALgAECgUJBgABLgAECgcJEAANAAAAAA==.Savant:BAAALgAECgMJAwAAAA==.Sayl:BAABLgAECn8XAAMWAAkJmwlCLgAsAQAWAAYJNQpCLgAsAQAYAAUJMwjpQwC0AAAAAA==.',
Sc='Scallywinkle:BAAALgAECgcJEAAAAA==.Scrap:BAABLgAECn8aAAMKAAkJ4hqLPgATAgAKAAgJcBqLPgATAgAZAAQJeRTgKwAQAQAAAA==.',
Se='Senova:BAAALgAECgIJAgAAAA==.',
Sh='Shadowghoul:BAAALgAECggJEAAAAA==.Shadowydern:BAABLgAECn8mAAMYAAkJZB/tBQDDAgAYAAkJZB/tBQDDAgAXAAEJ/RBpfwAzAAAAAA==.Shamewow:BAACLgAFFH8WAAIUAAUJfBkmBwBTAQAUAAUJfBkmBwBTAQAuAAQKfysAAhQACQlhGkoZAEwCABQACQlhGkoZAEwCAAAA.Shrimpboat:BAAALgAECgYJBQAAAA==.',
Si='Sicknnasty:BAACLgAFFH8UAAIdAAUJJxSLEQAHAQAdAAUJJxSLEQAHAQAuAAQKf0EAAx0ACAl8IqAHAGECAB0ACAl8IqAHAGECABAACAnIFH9JAK4BAAAA.',
Sl='Slayerz:BAAALgAECgYJBgAAAA==.',
Sn='Snattch:BAAALgADCgEJAQAAAA==.Snookismalls:BAAALgAECgcJEAAAAA==.',
So='Solarian:BAAALgADCgMJAwAAAA==.Solitary:BAABLgAECn8ZAAIQAAgJwRheLgALAgAQAAgJwRheLgALAgAAAA==.',
Sp='Speed:BAAALgAECgYJCwAAAA==.Spinach:BAAALgAECgMJAQABLgAECgYJBQANAAAAAA==.',
St='Starshopping:BAABLgAECn8UAAIVAAgJmiFlFQDWAgAVAAgJmiFlFQDWAgABLgAECgkJMAAMAPchAA==.',
Su='Sunari:BAAALgADCgQJBAAAAA==.',
Ta='Taewryn:BAAALgAFFAQJBAABLgAFFAgJKAAIABYiAA==.Talrip:BAABLgAECn8eAAIgAAkJVR3YBgAgAgAgAAkJVR3YBgAgAgAAAA==.',
Th='Thicctrix:BAAALgADCgcJDAAAAA==.Thundon:BAAALgADCgcJCQAAAA==.',
To='Toatem:BAAALgAECgUJBQAAAA==.Toro:BAACLgAFFH8bAAIaAAUJByLKCAB2AQAaAAUJByLKCAB2AQAuAAQKfysAAhoACQl3JGUFAFADABoACQl3JGUFAFADAAAA.',
Tr='Traitor:BAAALgADCgEJAQAAAA==.Trappynomnom:BAAALgAFFAIJAgAAAA==.Tree:BAACLgAFFH8PAAISAAQJBiTgDACuAQASAAQJBiTgDACuAQAuAAQKfxYAAhIABgmZI1geAEwCABIABgmZI1geAEwCAAAA.Treegrundler:BAAALgAECgYJEwAAAA==.Treeus:BAAALgAECgYJCQAAAA==.Trixulous:BAAALgADCgkJJQAAAA==.',
Tw='Twiigee:BAABLgAECn8XAAIIAAYJWSANIAABAgAIAAYJWSANIAABAgAAAA==.',
Tz='Tzungxie:BAABLgAECn8pAAIcAAkJWB1xCABeAgAcAAkJWB1xCABeAgAAAA==.',
Un='Unholylord:BAACLgAFFH8UAAIYAAUJaCNfCACAAQAYAAUJaCNfCACAAQAuAAQKfyIAAhgACQmpI8oEAEcDABgACQmpI8oEAEcDAAAA.',
Va='Vae:BAAALgAECgMJAwAAAA==.Vagbadge:BAAALgAECgkJEgABLgAFFAUJFAAYAGgjAA==.Varroww:BAAALgAECgYJEQAAAA==.',
Vo='Vosxo:BAAALgAECgEJAQAAAA==.',
['Ví']='Vígo:BAABLgAECn8gAAIBAAcJpQh/KADeAAABAAcJpQh/KADeAAAAAA==.',
Wa='Wado:BAAALgAECgEJAQAAAA==.',
We='Wellíngton:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgADCgYJBgAAAA==.',
Wi='Wicke:BAAALgADCgQJBAABLgAECgEJAgANAAAAAA==.',
Wo='Wolfthetree:BAAALgAECgUJCAAAAA==.',
Wy='Wystarr:BAAALgADCgIJAgAAAA==.',
Xa='Xamael:BAAALgADCgMJAwAAAA==.',
Xe='Xerkz:BAAALgAECgEJAQAAAA==.',
Ys='Ystarian:BAABLgAECn89AAQDAAkJrRvEAgBPAgADAAkJrRvEAgBPAgACAAgJBhQcHQDeAQAEAAEJGwHzTgAgAAAAAA==.',
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
