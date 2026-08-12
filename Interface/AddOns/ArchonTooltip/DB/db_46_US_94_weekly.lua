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

local lookup = {'Paladin-Holy','Warrior-Protection','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Druid-Restoration','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Mage-Frost','Warlock-Affliction','Mage-Fire','Priest-Holy','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood','Rogue-Assassination','Druid-Balance','DeathKnight-Frost','DemonHunter-Vengeance','Warlock-Demonology','DeathKnight-Unholy','Shaman-Elemental','Rogue-Subtlety','Druid-Feral','Monk-Brewmaster','Hunter-Survival','DemonHunter-Devourer','Monk-Windwalker','Warrior-Arms','Monk-Mistweaver','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aarchon:BAABLgAECn8qAAIBAAkJhB+ZCQDyAgABAAkJhB+ZCQDyAgAAAA==.',
Ad='Aduin:BAABLgAECn8lAAMCAAkJBBdGBQA/AQADAAkJbw6jNgBtAQACAAUJux1GBQA/AQAAAA==.',
Ae='Aedarelyn:BAABLgAECn8fAAMEAAgJkBB8GAAYAQAEAAgJkBB8GAAYAQAFAAMJoAy2DgByAAAAAA==.Aelisong:BAAALgADCgEJAQABLgAECgkJKwAGAB8QAA==.Aellita:BAABLgAECn8VAAIHAAYJZwhFqgDuAAAHAAYJZwhFqgDuAAAAAA==.Aeschylus:BAABLgAECn8WAAIEAAkJYg8IHQD3AAAEAAkJYg8IHQD3AAAAAA==.',
Af='Afkinlife:BAAALgADCgIJAgAAAA==.',
Ak='Akky:BAABLgAECn8tAAICAAkJKiH/BgCXAgACAAkJKiH/BgCXAgAAAA==.Aksafiya:BAABLgAECn9fAAMIAAkJhxRKGgDzAQAIAAkJhxRKGgDzAQAJAAEJWAINiwAcAAAAAA==.',
Al='Alal:BAABLgAECn8mAAIKAAgJDBLwEgBFAQAKAAgJDBLwEgBFAQAAAA==.Alandras:BAABLgAECn8tAAIDAAkJAAnkQQA9AQADAAkJAAnkQQA9AQAAAA==.Alaras:BAACLgAFFH8hAAIIAAgJUA+EBgC2AQAIAAgJUA+EBgC2AQAuAAQKfxcAAggACQnQFQ8aAA8CAAgACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8rAAILAAkJcxexBwDzAQALAAkJcxexBwDzAQAAAA==.Allrianne:BAAALgAECgQJEAAAAA==.Allyriae:BAABLgAECn8WAAIMAAgJDgkgCQD0AAAMAAgJDgkgCQD0AAAAAA==.Alstrumeria:BAAALgAECgEJAQAAAA==.Althoraty:BAABLgAECn8lAAINAAgJTx1gDwBzAgANAAgJTx1gDwBzAgAAAA==.',
Am='Ambilena:BAABLgAECn8vAAMIAAkJeBAvIQC8AQAIAAkJeBAvIQC8AQANAAYJVhhMLQBiAQAAAA==.Amyah:BAAALgADCgEJAQAAAA==.',
An='Andoros:BAABLgAECn86AAIGAAkJax6bEADMAgAGAAkJax6bEADMAgAAAA==.Angiliana:BAABLgAECn8UAAIOAAUJAw8sPQDCAAAOAAUJAw8sPQDCAAAAAA==.Angvall:BAAALgAECgYJCAABLgAFFAMJBAAPAAAAAA==.Animainiac:BAAALgAECgYJBgABLgAECgkJKQAQAGcSAA==.Anzurath:BAABLgAECn8pAAIEAAkJzxVqTgDcAQAEAAkJzxVqTgDcAQAAAA==.',
Ap='Apheron:BAAALgAECgEJAQABLgAECgkJMAARANUgAA==.Applebow:BAABLgAECn8uAAISAAkJ/hFkCAAAAQASAAkJ/hFkCAAAAQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardalel:BAAALgADCgEJAQAAAA==.Ardiand:BAABLgAECn8bAAITAAkJsBetAABDAgATAAkJsBetAABDAgAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgkJEgAAAA==.Armas:BAAALgAECggJCQAAAA==.Arylin:BAABLgAECn82AAIKAAkJlSMiCgApAwAKAAkJlSMiCgApAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8eAAMCAAcJ+BT+CQCuAAACAAcJShT+CQCuAAADAAIJHhH5KwAxAAAAAA==.Asiain:BAABLgAFFH8FAAIUAAUJOQskFQDdAAAUAAUJOQskFQDdAAABLgAFFAkJLgADAGgdAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAPAAAAAA==.Asky:BAAALgADCgYJCQABLgAECgkJKgAKAHEDAA==.Asmodean:BAAALgAECgEJAgAAAA==.Asnabel:BAABLgAECn83AAIVAAkJtRGUAgCyAQAVAAkJtRGUAgCyAQAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astrai:BAAALgADCgcJBwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCgASAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgAECgYJEgAAAA==.Ayden:BAABLgAECn8jAAMWAAkJTRooAwA9AQAOAAkJMBmBGAC/AQAWAAQJ+BsoAwA9AQAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAPAAAAAA==.Banshee:BAAALgAECgMJAwAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.Belthar:BAAALgAECgUJBQABLgAFFAIJAwAPAAAAAA==.Benkei:BAAALgAECgQJBQAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgMJBQAAAA==.',
Bl='Blee:BAABLgAECn8+AAMJAAkJNBDrBwByAQAJAAkJNBDrBwByAQAIAAQJlgWRSgCwAAAAAA==.Bloodbourne:BAAALgAECgEJAQAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.Bluudclaaw:BAAALgAECgYJBwABLgAFFAMJBAAPAAAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8lAAIXAAcJVh6rOAD3AQAXAAcJVh6rOAD3AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8uAAIHAAkJxiHrHwBoAgAHAAkJxiHrHwBoAgAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8fAAIYAAkJuhAjdgB3AQAYAAkJuhAjdgB3AQAAAA==.Brood:BAABLgAECn8rAAIYAAkJyBRRUQDPAQAYAAkJyBRRUQDPAQAAAA==.Brundles:BAAALgAECgYJBgAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn9JAAMZAAkJagorCgArAQAZAAkJagorCgArAQAQAAUJFgjEkAC3AAAAAA==.',
Ca='Cailaranel:BAABLgAECn8wAAMaAAkJigkUJAB0AQAaAAkJPggUJAB0AQATAAcJaQlUEAAfAQAAAA==.Calaul:BAABLgAECn80AAMEAAkJ6hSUSgDmAQAEAAkJ6hSUSgDmAQAFAAUJnAaVDwBqAAAAAA==.Calenbraga:BAABLgAECn9ZAAIbAAkJ3x4gAQBgAgAbAAkJ3x4gAQBgAgAAAA==.Calisim:BAABLgAECn8hAAIXAAYJMwcZwADLAAAXAAYJMwcZwADLAAAAAA==.Callidae:BAABLgAECn8qAAINAAkJBxEwHADlAQANAAkJBxEwHADlAQAAAA==.Calmnbald:BAABLgAECn8ZAAIcAAcJeBfGPAAIAQAcAAcJeBfGPAAIAQAAAA==.Caloh:BAAALgAECggJDgAAAA==.Cantallbis:BAAALgADCgcJBwAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8lAAIdAAkJlgwuHQCzAQAdAAkJlgwuHQCzAQAAAA==.Cataryn:BAABLgAECn8mAAIHAAkJNSRwDwDVAgAHAAkJNSRwDwDVAgAAAA==.Catt:BAABLgAECn9LAAIBAAkJGBkDFABvAgABAAkJGBkDFABvAgAAAA==.',
Ce='Cellebur:BAABLgAECn8rAAIHAAkJCgs9FwAoAQAHAAkJCgs9FwAoAQAAAA==.Ceta:BAABLgAECn87AAINAAkJDhyuDQCLAgANAAkJDhyuDQCLAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAACLgAFFH8HAAMZAAMJWQvHTABjAAAZAAIJ7QTHTABjAAAQAAIJ3QIYeQBMAAAuAAQKfysAAxAACAncEfA9ALYBABAACAncEfA9ALYBABkABwm2GRMuAIoBAAAA.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn9SAAIKAAkJlguIFAA3AQAKAAkJlguIFAA3AQAAAA==.Cinderelah:BAAALgAECgEJAQAAAA==.Cirillia:BAAALgAECgEJAQAAAA==.Cizean:BAABLgAECn8qAAIKAAkJcQOeOABsAAAKAAkJcQOeOABsAAAAAA==.',
Co='Corhane:BAAALgADCgUJBQAAAA==.',
Cr='Craivan:BAAALgAECgYJEAAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crill:BAAALgAECgYJBwAAAA==.Crilly:BAABLgAECn8rAAIKAAkJZRj5OgAtAgAKAAkJZRj5OgAtAgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQAPAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAABLgAECn8cAAIQAAkJ+AyHGwCyAAAQAAkJ+AyHGwCyAAAAAA==.Cyrr:BAAALgAECggJDwAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8tAAMaAAkJPBjpFgDlAQAaAAkJPBjpFgDlAQATAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgAECgYJBwAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8mAAISAAkJ8CQHBAD5AgASAAkJ8CQHBAD5AgAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgIJBQABLgAECgkJJgASAPAkAA==.Delvarrieth:BAABLgAECn8qAAIFAAkJvQ3dHgAdAQAFAAkJvQ3dHgAdAQAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Demonzar:BAAALgAECgYJCgAAAA==.Demzy:BAAALgAECgYJBwAAAA==.Denth:BAABLgAECn8gAAIEAAkJsQ4EbgCSAQAEAAkJsQ4EbgCSAQAAAA==.Dercuur:BAACLgAFFH8JAAIZAAMJBRq7FwDbAAAZAAMJBRq7FwDbAAAuAAQKfx0AAhkACAlVF84kAMEBABkACAlVF84kAMEBAAAA.Devoursol:BAABLgAECn85AAMeAAkJlQz+WAB8AQAeAAkJaAz+WAB8AQAOAAIJrg45XABvAAAAAA==.',
Di='Dipndots:BAAALgAECgYJBwABLgAECgkJJgASAPAkAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgAECgcJEAAAAA==.Drainmee:BAABLgAECn8oAAMJAAgJBRVzMABcAQAJAAgJBRVzMABcAQAIAAUJagSxZQCFAAAAAA==.Draknol:BAAALgAECgEJAQAAAA==.Dravorik:BAAALgAECgQJBAAAAA==.Dreadspark:BAABLgAECn8dAAMXAAkJ8xyaHgBtAgAXAAkJTRyaHgBtAgALAAQJdx0aGAC6AAAAAA==.Dregoth:BAABLgAECn8tAAIYAAkJdAlDEwAdAQAYAAkJdAlDEwAdAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.Dsshiva:BAAALgAECgEJAwAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8hAAMGAAkJ4R5kEAC0AgAGAAkJ4R5kEAC0AgAUAAEJxgkemgAnAAAAAA==.',
Ea='Eathur:BAAALgAECgYJBgAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
Ed='Edeveren:BAAALgAECgYJBwAAAA==.',
El='Elunariel:BAAALgAECgEJAgABLgAECgkJHQAXAPMcAA==.Elynth:BAABLgAECn8nAAIXAAkJcxx2IgBYAgAXAAkJcxx2IgBYAgAAAA==.',
En='Endlessyueh:BAABLgAECn8lAAMEAAcJxA8hyAD9AAAEAAYJCxAhyAD9AAABAAcJFwc2EgCNAAAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJHQAXAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAYJEAAEAPoMAA==.',
Ex='Excelsior:BAAALgAECgcJBAAAAA==.',
Fa='Faethian:BAACLgAFFH8UAAIFAAUJSiFwAwBxAQAFAAUJSiFwAwBxAQAuAAQKfywAAgUACAk7JacDANUCAAUACAk7JacDANUCAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8xAAIKAAkJ6wnDiwBgAQAKAAkJ6wnDiwBgAQAAAA==.Fangren:BAABLgAECn8oAAIHAAYJyBIUIQDdAAAHAAYJyBIUIQDdAAAAAA==.Fariah:BAAALgAECgUJEwAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAABLgAECn8YAAIfAAcJ6QeSRwDhAAAfAAcJ6QeSRwDhAAAAAA==.',
Fe='Felicja:BAAALgAFFAEJAgABLgAFFAkJKgAgANMWAA==.Felscythe:BAABLgAECn8pAAIcAAkJnwGSCwB0AAAcAAkJnwGSCwB0AAAAAA==.Felynn:BAABLgAECn8sAAIBAAkJgxj9FQBcAgABAAkJgxj9FQBcAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feresdenn:BAAALgADCgQJBAAAAA==.Feyrha:BAAALgADCgYJBgABLgAECgkJRQAHAIoSAA==.',
Fi='Fiadh:BAAALgAECgQJBgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8kAAIhAAkJXR0OHwAhAgAhAAkJXR0OHwAhAgAAAA==.',
Fl='Flaeli:BAABLgAECn8rAAIKAAkJzhlTFQAwAQAKAAkJzhlTFQAwAQAAAA==.Flameshot:BAAALgADCgkJCQABLgAECgkJLwAiAHUQAA==.Flemish:BAABLgAECn8YAAIZAAgJLxXrKwCWAQAZAAgJLxXrKwCWAQAAAA==.Flextame:BAAALgAECgQJEQAAAA==.Flipalicious:BAABLgAECn9AAAMQAAkJehyQEQDCAgAQAAkJehyQEQDCAgAZAAIJSxRingA9AAAAAA==.Flipanomicon:BAAALgADCgYJDgAAAA==.Flipkicks:BAAALgADCgMJAwAAAA==.Flipmode:BAAALgADCgEJAQAAAA==.',
Fr='Freyalise:BAABLgAECn8eAAIIAAcJSRgAKgCBAQAIAAcJSRgAKgCBAQABLgAECggJGgAVAH0cAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Fu='Furriousyueh:BAAALgAECgQJCAAAAA==.',
['Fë']='Fënrír:BAAALgAECgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn9FAAIHAAkJihJ0DQCZAQAHAAkJihJ0DQCZAQAAAA==.Gallimaufrey:BAAALgAECgMJAwAAAA==.Gangstafred:BAAALgADCgYJBgAAAA==.Ganzar:BAAALgAECgEJAQAAAA==.Gazo:BAABLgAECn8YAAMIAAcJRBnGHgDPAQAIAAcJRBnGHgDPAQAJAAEJqxE7IwA9AAABLgAECgkJMAAfAJoiAA==.',
Ge='Gemboss:BAABLgAECn9OAAMEAAkJHSIvDgD0AgAEAAkJHSIvDgD0AgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8uAAMKAAkJmxO4XwDBAQAKAAkJmxO4XwDBAQAjAAMJoAbAFQBuAAAAAA==.Geye:BAAALgADCgEJAQAAAA==.',
Gi='Gianavel:BAABLgAECn8yAAIfAAkJsAstLQBYAQAfAAkJsAstLQBYAQAAAA==.Ginodh:BAABLgAECn8OAAIeAAgJtQ1eewApAQAeAAgJtQ1eewApAQABLgAECgkJGQASAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQASAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQASAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQASAPwNAA==.Girth:BAAALgAECgUJCgAAAA==.Gizelli:BAAALgAFFAEJAgAAAA==.',
Gl='Glorby:BAAALgAECgQJBAABLgAFFAIJBQAhAGMXAA==.',
Go='Goldstandard:BAAALgADCgEJAQABLgAFFAIJBQAhAGMXAA==.Gordonnpr:BAAALgAECgYJDQAAAA==.',
Gr='Grettlynne:BAAALgAECgEJAQAAAA==.Groblock:BAAALgADCgYJEgAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAhAGMXAA==.Grubetsella:BAACLgAFFH8FAAIhAAIJYxduDwClAAAhAAIJYxduDwClAAAuAAQKfzgAAiEACQlfIeEMAM0CACEACQlfIeEMAM0CAAAA.Grumpÿ:BAAALgADCgYJEgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIeAAYJXBvFUAC0AQAeAAYJXBvFUAC0AQAAAA==.Gulraan:BAAALgAECgMJAwAAAA==.Gumpers:BAABLgAECn8vAAIiAAkJdRDWHQBfAQAiAAkJdRDWHQBfAQAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gurl:BAAALgADCgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAABLgAECn8lAAIUAAkJkQXpFACNAAAUAAkJkQXpFACNAAAAAA==.',
Ha='Haggrum:BAAALgADCgQJBAAAAA==.Halfamazing:BAAALgAECgYJDAAAAA==.Hanoumatoi:BAAALgAECgkJDAAAAA==.Haradar:BAAALgADCgEJAQABLgAECggJJgAFAKkTAA==.Haralambos:BAABLgAECn8mAAIFAAgJqROoBABeAQAFAAgJqROoBABeAQAAAA==.Haralogain:BAAALgAECgEJAQABLgAECggJJgAFAKkTAA==.Harithon:BAABLgAECn8wAAIRAAkJ1SDXAwC9AgARAAkJ1SDXAwC9AgAAAA==.Harlar:BAAALgAECgIJAwAAAA==.Hatebug:BAAALgAECgcJBwAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoBx5DADHAgABAAkJoBx5DADHAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Helbrede:BAAALgADCgYJBgAAAA==.Heledosia:BAABLgAECn8pAAICAAkJ5ANfKwDcAAACAAkJ5ANfKwDcAAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8rAAIKAAYJ4wzYIQDVAAAKAAYJ4wzYIQDVAAAAAA==.Heyokagi:BAABLgAECn8vAAQbAAkJNyIrAgANAwAbAAkJNyIrAgANAwAiAAIJ1BS5JgBnAAAGAAEJXwhz2wAqAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJHQAXAPMcAA==.Hordkilla:BAABLgAECn8wAAIEAAkJxAfflwBFAQAEAAkJxAfflwBFAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8lAAIEAAgJLxxGQgAAAgAEAAgJLxxGQgAAAgAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn82AAMeAAkJ2BwkFgCSAgAeAAkJ2BwkFgCSAgAWAAEJphoiLgBKAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.Hymno:BAAALgAECgEJAgAAAA==.',
Ic='Ic:BAAALgAECgQJBAABLgAECgkJQAACAMEYAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAABLgAECn8jAAQGAAkJChDzBgB3AQAGAAkJChDzBgB3AQAUAAcJsw/SFACOAAAiAAEJmAMeiAAWAAAAAA==.',
Im='Imathdal:BAABLgAECn8tAAIkAAkJvRPFAQCmAQAkAAkJvRPFAQCmAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAPAAAAAA==.Insoniacyun:BAABLgAECn8cAAIKAAgJvws+jABfAQAKAAgJvws+jABfAQAAAA==.',
Is='Iselian:BAAALgAECgkJKQAAAQ==.Ishanu:BAABLgAECn8iAAIIAAkJ8B50AgBDAgAIAAkJ8B50AgBDAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAPAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgAECgkJEgABLgAFFAIJAgAPAAAAAA==.Jax:BAACLgAFFH8NAAIKAAQJRCLATQBDAQAKAAQJRCLATQBDAQAuAAQKfykAAgoACAlFIxATADUDAAoACAlFIxATADUDAAAA.',
Jb='Jbelbueno:BAAALgAECgYJEgAAAA==.Jblockiv:BAAALgADCgcJDAAAAA==.Jblovo:BAAALgAECgUJBQAAAA==.Jbmago:BAAALgAECgcJCAAAAA==.Jbprimero:BAAALgAECgYJBwAAAA==.Jbshami:BAABLgAECn9BAAMQAAkJLiCBEgC5AgAQAAkJLiCBEgC5AgAZAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn89AAIjAAkJWg6IBACrAQAjAAkJWg6IBACrAQAAAA==.Jetfires:BAABLgAECn9UAAIHAAkJPyDpDADsAgAHAAkJPyDpDADsAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn9BAAIfAAkJMgqHBgA1AQAfAAkJMgqHBgA1AQAAAA==.Jinnwoo:BAAALgAECgQJBQAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jovie:BAAALgAECgEJAQAAAA==.Jozhua:BAABLgAECn8bAAIHAAkJ2g3CJADIAAAHAAkJ2g3CJADIAAAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgAECgUJEQAAAA==.Kaelaya:BAABLgAECn8dAAIkAAcJOQqoHADJAAAkAAcJOQqoHADJAAAAAA==.Kaelorien:BAABLgAECn89AAIhAAkJKRJoJgDyAQAhAAkJKRJoJgDyAQAAAA==.Kaetta:BAABLgAECn8XAAIKAAgJ0APiwwAEAQAKAAgJ0APiwwAEAQAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgYJDgAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAABLgAECn8pAAIFAAkJvBB5BgAaAQAFAAkJvBB5BgAaAQAAAA==.Kaldevayn:BAABLgAECn8mAAMBAAkJFxiGAgBKAgABAAkJFxiGAgBKAgAEAAYJgg3+GAAVAQAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8zAAIeAAYJ5hTjDgAbAQAeAAYJ5hTjDgAbAQAAAA==.Kalyna:BAABLgAECn8YAAMjAAcJlwk7BgDDAAAjAAcJlwk7BgDDAAAKAAcJ+wLhMQCKAAAAAA==.Kandandris:BAAALgAECgcJCAAAAA==.Kanhoa:BAAALgAECgIJAgAAAA==.Kardanis:BAABLgAECn8uAAIQAAkJviRqAgCiAwAQAAkJviRqAgCiAwAAAA==.Kardzuni:BAAALgADCgEJAQAAAA==.Kashe:BAABLgAECn8nAAMBAAgJchvoCAA1AQABAAcJCxroCAA1AQAEAAIJIwyOTwBOAAAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Kasume:BAAALgAECgIJAwAAAA==.Katavia:BAABLgAECn8pAAIQAAkJZxKHPAC8AQAQAAkJZxKHPAC8AQAAAA==.Katrazath:BAAALgAECgMJAwAAAA==.Kaydencia:BAABLgAECn8XAAIEAAYJvxET0gDwAAAEAAYJvxET0gDwAAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgQJBgAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Kc='Kcelo:BAAALgAECgQJBAAAAA==.',
Ke='Keldormu:BAAALgADCgkJCQAAAA==.Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.Keyallandron:BAAALgAECgIJAgABLgAECggJEwAPAAAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgAECgYJCAAAAA==.Khortical:BAAALgADCgkJCQABLgAECgkJMAARANUgAA==.',
Ki='Ki:BAAALgAECgQJBQAAAA==.Kiddow:BAABLgAECn8YAAIKAAkJfRHmGgAEAQAKAAkJfRHmGgAEAQAAAA==.Kierea:BAAALgAECgMJAwAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgAECgEJAQAAAA==.Kiri:BAAALgADCgkJEQAAAA==.Kitamii:BAABLgAECn8UAAIbAAYJdRbHEQCQAQAbAAYJdRbHEQCQAQAAAA==.Kivrin:BAABLgAECn8XAAIIAAgJ3wzWCAA+AQAIAAgJ3wzWCAA+AQAAAA==.Kiára:BAAALgAECgEJAQAAAA==.',
Kr='Kringlë:BAABLgAECn8oAAIHAAkJ3SDEGACSAgAHAAkJ3SDEGACSAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kurumi:BAAALgAECgYJCQAAAA==.Kushwizard:BAAALgADCgQJBQAAAA==.Kuunko:BAAALgAECgEJAQAAAA==.',
Kw='Kwo:BAAALgADCgMJAwAAAA==.',
Ky='Kymma:BAABLgAECn81AAIEAAkJIw4mIADhAAAEAAkJIw4mIADhAAAAAA==.Kyunix:BAAALgAECgYJBgAAAA==.',
La='Lagoriatsua:BAABLgAECn8ZAAIZAAgJlQZYUgDvAAAZAAgJlQZYUgDvAAAAAA==.Laitue:BAAALgAECgQJDAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAABLgAECn8dAAMIAAcJ3hodBQCpAQAIAAcJ3hodBQCpAQAJAAUJIxR3CgA3AQAAAA==.Lazengann:BAABLgAECn8mAAMeAAkJnRanOwDZAQAeAAkJERWnOwDZAQAOAAIJ/BnGXABUAAAAAA==.',
Le='Leafbane:BAAALgAECgMJAwAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAABLgAECn8gAAMRAAkJKQbcDAB6AAARAAkJKQbcDAB6AAAQAAIJkgKWzwA8AAAAAA==.Leiris:BAABLgAECn88AAIEAAkJDRFrWgC+AQAEAAkJDRFrWgC+AQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Leonaa:BAAALgADCgYJBgAAAA==.Letifer:BAAALgAECgMJAwAAAA==.Leucetios:BAAALgAECgUJDgAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8iAAINAAkJRxmTDgB/AgANAAkJRxmTDgB/AgAAAA==.Lightbeard:BAABLgAECn8pAAQBAAcJHRxYHgAQAgABAAcJHRxYHgAQAgAEAAIJ+wUDbwFJAAAFAAEJ4A/gUwApAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8WAAIEAAgJ7RgPbQCUAQAEAAgJ7RgPbQCUAQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgAECgYJCwAAAA==.Liubing:BAAALgADCgkJDwABLgAECgMJDwAPAAAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lochli:BAAALgAECgUJCgAAAA==.Loginus:BAAALgAECgUJBQAAAA==.Lorredain:BAAALgAECgUJCwAAAA==.Lothaire:BAAALgADCgEJAQABLgADCgIJAgAPAAAAAA==.Lothwen:BAAALgAECggJEgAAAA==.Louisachan:BAAALgADCgUJBQABLgAFFAEJAgAPAAAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8dAAINAAUJqxCzFAAeAQANAAUJqxCzFAAeAQAuAAQKfzcAAg0ACQmPFrUXABACAA0ACQmPFrUXABACAAAA.Luxinine:BAABLgAECn8tAAMIAAkJuyB6BgDqAgAIAAkJuyB6BgDqAgAJAAIJsxTbFgCEAAAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgAECgYJBgABLgAECgkJJAAlAGohAA==.',
Ma='Madhawi:BAABLgAECn9BAAMJAAgJhyXJAABmAwAJAAgJhyXJAABmAwANAAIJOhSGawB9AAAAAA==.Magamon:BAABLgAECn8wAAIKAAkJBxhkOgAwAgAKAAkJBxhkOgAwAgAAAA==.Magamus:BAAALgADCgYJBgAAAA==.Mahndarb:BAABLgAECn8YAAMEAAYJexBdHwDnAAAEAAYJexBdHwDnAAABAAMJ1wJRfABUAAABLgAECggJJQANAE8dAA==.Majima:BAAALgAECgYJDgAAAA==.Makedeader:BAAALgAECgkJBgAAAA==.Malfuriia:BAABLgAECn8qAAIQAAkJdxmuLAAGAgAQAAkJdxmuLAAGAgAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAABLgAECn8UAAMkAAcJZhVdAwAiAQAkAAYJYxRdAwAiAQAHAAEJdBokTABIAAAAAA==.Margerdria:BAABLgAECn8cAAIIAAgJNxJDBwBlAQAIAAgJNxJDBwBlAQAAAA==.Maskelle:BAABLgAECn8uAAIWAAkJvBGTDgBnAQAWAAkJvBGTDgBnAQAAAA==.Mauugrim:BAABLgAECn8qAAIYAAkJMwkYHQDPAAAYAAkJMwkYHQDPAAAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAABLgAECn8iAAIEAAkJNhZ2cACNAQAEAAkJNhZ2cACNAQAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8lAAIEAAgJEQvjrAAkAQAEAAgJEQvjrAAkAQAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8kAAMlAAkJaiFABQAPAgAlAAkJaiFABQAPAgAmAAMJOhMmKwCTAAAAAA==.Mel:BAAALgAECgMJDwAAAA==.Melanara:BAABLgAECn9LAAIKAAkJUg8tEABmAQAKAAkJUg8tEABmAQAAAA==.Melstrom:BAAALgAECgkJEwAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgAECgYJEgAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAABLgAECn8XAAIjAAkJQRa9AwDVAQAjAAkJQRa9AwDVAQAAAA==.Miyävii:BAABLgAECn8YAAIFAAkJxxNGFwBmAQAFAAkJxxNGFwBmAQAAAA==.',
Mj='Mjsage:BAABLgAECn8kAAIHAAkJGR6yJABQAgAHAAkJGR6yJABQAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQABLgAECgkJFQAHAMkZAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8lAAIIAAkJqRspCABMAQAIAAkJqRspCABMAQAAAA==.Mooasha:BAAALgAECgEJAQABLgAECgkJKQAQAGcSAA==.Moonflowers:BAACLgAFFH8gAAIGAAkJpxcJCAB9AgAGAAkJpxcJCAB9AgAuAAQKfy8AAgYACAmcJM4HAA8DAAYACAmcJM4HAA8DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAcJJgAYAFMUAA==.Morginoth:BAAALgADCgcJBwAAAA==.Morregu:BAAALgAECgQJBQAAAA==.Mousekee:BAABLgAECn8qAAINAAkJkg2UJwCJAQANAAkJkg2UJwCJAQAAAA==.',
Mu='Muku:BAAALgADCgkJCQABLgAECgkJUQAKANsSAA==.Murdrmitts:BAABLgAECn80AAIbAAkJzhN7AgC6AQAbAAkJzhN7AgC6AQAAAA==.Muross:BAAALgAECgEJAQAAAA==.Mustikka:BAABLgAECn8gAAIbAAgJHRTlBQABAQAbAAgJHRTlBQABAQAAAA==.',
My='Mystikah:BAAALgAECgEJAQAAAA==.Myuriyanka:BAABLgAECn8pAAMZAAkJoBOGJADDAQAZAAkJoBOGJADDAQAQAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwAPAAAAAA==.',
Na='Naahommii:BAABLgAECn8hAAIHAAkJxRRLQgDbAQAHAAkJxRRLQgDbAQAAAA==.Nachtpranke:BAABLgAECn8eAAIGAAkJMyArGACFAgAGAAkJMyArGACFAgAAAA==.Nadron:BAAALgAECgYJDAAAAA==.Naevala:BAAALgAECgkJCwAAAA==.Nagualli:BAAALgAECgQJBQAAAA==.Nastychungus:BAAALgAECgMJAwAAAA==.Navira:BAAALgADCgYJBQAAAA==.',
Ne='Negargra:BAABLgAECn8wAAMXAAYJUxSHDgAbAQAXAAYJUxSHDgAbAQAnAAEJcgMufAAkAAAAAA==.Nekwid:BAAALgADCgIJAgAAAA==.Nephadin:BAABLgAECn8dAAMEAAgJpAr7uQARAQAEAAgJpAr7uQARAQABAAUJnAbNWQDPAAAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgYJDgAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nightrunner:BAAALgADCgYJBQAAAA==.Nighttiger:BAABLgAECn8nAAMGAAgJXBJEBwBpAQAGAAgJXBJEBwBpAQAUAAEJSQcDLQAaAAAAAA==.Nikooli:BAABLgAECn8qAAMOAAkJWxnlBQB2AQAOAAkJWxnlBQB2AQAWAAEJ+AYlPQAaAAAAAA==.Nimb:BAAALgAECgEJBAAAAA==.',
No='Nokkoh:BAAALgADCgcJCgAAAA==.Nolime:BAAALgAECgYJBwAAAA==.Noodledragon:BAAALgAECgYJBwAAAA==.Noopsie:BAABLgAECn8/AAMGAAkJmRGzBQCnAQAGAAkJmRGzBQCnAQAUAAEJzw10KAAqAAAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAgJKwAmADQQAA==.Nooters:BAAALgAECgEJAQABLgAFFAgJKwAmADQQAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMJAAgJxhqHFwAZAgAJAAcJLhyHFwAZAgAIAAcJsBxlLAByAQAAAA==.Notpeepuddle:BAAALgAECgEJAQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Nu='Nuhnoo:BAAALgADCgkJCQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8tAAIEAAkJChtyTADhAQAEAAkJChtyTADhAQAAAA==.Nyxalia:BAAALgAECgYJCAAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMjAAkJbgM/EgCgAAAKAAkJWQMu4ADaAAAjAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBQAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgAECgIJAgAAAA==.Olympia:BAABLgAECn8vAAIFAAkJ3A1WHQAqAQAFAAkJ3A1WHQAqAQAAAA==.',
Or='Oraclemega:BAABLgAECn80AAIKAAkJBSA5EAD6AgAKAAkJBSA5EAD6AgAAAA==.Oranash:BAAALgADCgcJCQAAAA==.Orweyna:BAAALgAECggJDwAAAA==.',
Os='Oscarmikey:BAACLgAFFH8oAAMGAAUJ3BVuDgBBAQAGAAUJ3BVuDgBBAQAUAAIJsg7eIAB5AAAuAAQKf0oABQYACQmGHoAQAM0CAAYACQmGHoAQAM0CABQABgn9FXsNAOEAABsAAQlMAr1hACAAACIAAQkAAOuUAAAAAAAA.Oshu:BAAALgAECgYJBgAAAA==.',
Ot='Ottoshot:BAABLgAECn8oAAIHAAkJExSLHAD9AAAHAAkJExSLHAD9AAAAAA==.',
Ov='Overlordock:BAAALgAFFAEJAQAAAA==.',
Ow='Owlaf:BAAALgAECgUJBQAAAA==.',
Oz='Ozzric:BAAALgADCgEJAQAAAA==.',
['Oö']='Oöps:BAABLgAECn8aAAIGAAkJKQ3tBwBUAQAGAAkJKQ3tBwBUAQAAAA==.',
Pa='Paksen:BAAALgAECgEJAQAAAA==.Panamone:BAABLgAECn8nAAMbAAkJnSTlAgCXAQAbAAkJnSTlAgCXAQAGAAIJBRZfmACBAAAAAA==.Pandeism:BAABLgAECn80AAMRAAkJZxTZDgDDAQARAAgJHxTZDgDDAQAQAAcJoBchRACdAQAAAA==.Papagrip:BAABLgAECn82AAMVAAkJ7xJZDACyAQAVAAkJ7xJZDACyAQAYAAkJ6Qr6pgAhAQAAAA==.Patrin:BAABLgAECn8gAAIKAAgJZw3ggwBwAQAKAAgJZw3ggwBwAQAAAA==.Paulee:BAAALgADCgkJDgAAAA==.',
Pe='Peanutbritle:BAABLgAECn8qAAISAAkJaAZrLgDrAAASAAkJaAZrLgDrAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAFFAcJAQAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.Phean:BAAALgAECgEJAQAAAA==.Phylah:BAAALgAECgMJBAAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAECggJKQAEAA8lAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgQJBwAAAA==.Porterhouze:BAAALgAECgEJAgAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgYJBwAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAIGAAcJWRnvMwDZAQAGAAcJWRnvMwDZAQAAAA==.Ramsees:BAEALgAECgEJAQABLgAECgkJOgAIALMfAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Redrollin:BAAALgAECgIJAgAAAA==.Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAYJMQAjAGklAA==.Reyrocko:BAAALgAFFAEJAQAAAA==.Reyva:BAAALgADCgEJAQAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAQJDQAIABsdAA==.Rezdk:BAAALgAECggJCAABLgAFFAQJDQAIABsdAA==.Rezhunt:BAABLgAFFH8FAAMkAAQJJxn/GQDjAAAkAAMJrhj/GQDjAAAdAAEJkhr2LwBUAAABLgAFFAQJDQAIABsdAA==.Rezmonk:BAAALgAFFAEJAQABLgAFFAQJDQAIABsdAA==.Rezshift:BAABLgAECn8bAAMUAAgJwhzjFQAgAgAUAAgJwhzjFQAgAgAGAAQJBRbtbwAFAQABLgAFFAQJDQAIABsdAA==.Rezvoid:BAACLgAFFH8NAAMIAAQJGx0AFQA9AQAIAAQJGx0AFQA9AQANAAIJgyHwIgCjAAAuAAQKfzQAAwgACQkQI84GAOUCAAgACQkQI84GAOUCAA0AAgmjIPFJAL0AAAAA.',
Rh='Rhage:BAAALgAECgMJCgAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIYAAcJlRKnngAuAQAYAAcJlRKnngAuAQAAAA==.Roxane:BAABLgAECn8lAAIUAAkJxQmQMABbAQAUAAkJxQmQMABbAQAAAA==.',
Ru='Runningelk:BAABLgAECn8xAAIiAAkJvBLbFQClAQAiAAkJvBLbFQClAQAAAA==.Runscapemain:BAABLgAECn8sAAMEAAkJQBjwVADLAQAEAAkJQBjwVADLAQAFAAYJ/RAUIwD8AAAAAA==.',
Ry='Ryeti:BAAALgADCgkJFwAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgAOAAEkAA==.',
Sa='Saintulrick:BAAALgAECgIJAwAAAA==.Sajuice:BAACLgAFFH8HAAIkAAUJPwW5GwDSAAAkAAUJPwW5GwDSAAAuAAQKfyYAAiQACAnAGyIKAM8BACQACAnAGyIKAM8BAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn87AAMNAAkJmg7KCgD5AAANAAkJmg7KCgD5AAAIAAQJzAcbFwB+AAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.Satsukii:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAPAAAAAA==.',
Se='Seeyen:BAACLgAFFH8bAAIHAAYJ9hW8MwBGAQAHAAYJ9hW8MwBGAQAuAAQKfzAAAgcACQnfHgUHAB8DAAcACQnfHgUHAB8DAAAA.Seeyenn:BAAALgAECgMJAwAAAA==.Selendriel:BAAALgADCggJDwAAAA==.Selfdestruct:BAABLgAECn8iAAIEAAgJoxA/EABqAQAEAAgJoxA/EABqAQAAAA==.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8lAAIlAAkJgwrgCgBsAQAlAAkJgwrgCgBsAQAAAA==.Seren:BAAALgAFFAEJAwABLgAFFAkJJgAKABoLAA==.Serenityhate:BAABLgAECn8qAAMNAAgJ6AvfCwDjAAANAAgJ6AvfCwDjAAAIAAEJAABzoAAAAAAAAA==.',
Sh='Shaaydo:BAAALgAECgEJBAAAAA==.Shaayjynxx:BAAALgAECgEJAQAAAA==.Shaaytheyha:BAAALgAECgMJAwAAAA==.Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJCAAAAA==.Shandrilyn:BAABLgAECn8YAAIIAAcJIARnUQDMAAAIAAcJIARnUQDMAAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheadeo:BAAALgAECgEJAQAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAImAAkJwBQgGABQAQAmAAkJwBQgGABQAQAAAA==.Shiziuno:BAAALgAECgQJDgAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.Sionarra:BAAALgAECgEJAQAAAA==.',
Sj='Sjðfn:BAAALgAECgkJAgAAAA==.',
Sk='Skala:BAABLgAECn8YAAIoAAkJThZnHADyAQAoAAkJThZnHADyAQAAAA==.Skibbie:BAACLgAFFH8gAAMoAAcJogwBHgBwAQAoAAcJogwBHgBwAQAlAAQJOwoCBgD9AAAuAAQKfx4ABCgACQk4GF8QAHMCACgACQk4GF8QAHMCACYABAmHDpImALgAACUABQnOBpAsALcAAAAA.Skibbward:BAABLgAECn8zAAQiAAgJTiS4AQAyAwAiAAgJTiS4AQAyAwAUAAUJxQ9jVADUAAAGAAYJ6QrsggDSAAABLgAFFAcJIAAoAKIMAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAABLgAECn8XAAIQAAgJRR4vFACqAgAQAAgJRR4vFACqAgAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Slickdeath:BAAALgAECgIJBAAAAA==.Slickpraying:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJBgABLgAECgIJBwAPAAAAAA==.',
Sm='Smackdogg:BAACLgAFFH8IAAIUAAUJKBxOFwBgAQAUAAUJKBxOFwBgAQAuAAQKfxkAAhQABwk9HRcdABgCABQABwk9HRcdABgCAAEuAAUUCQkxABkAch4A.',
Sn='Snorpuff:BAAALgAECgUJBQAAAA==.',
So='Solteria:BAABLgAECn8VAAILAAcJqAk/DgBOAQALAAcJqAk/DgBOAQABLgAECgkJAgAPAAAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAABLgAECn8ZAAIOAAcJxxDFKAA2AQAOAAcJxxDFKAA2AQAAAA==.Sorvina:BAABLgAECn84AAIXAAkJdBKsQADaAQAXAAkJdBKsQADaAQAAAA==.Soulcross:BAAALgAECgYJBwAAAA==.Soulflame:BAABLgAECn9RAAIKAAkJ2xKZEABhAQAKAAkJ2xKZEABhAQAAAA==.Soulshifter:BAABLgAECn8aAAIUAAcJnwulRQD2AAAUAAcJnwulRQD2AAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECggJJgAFAKkTAA==.',
Sp='Spacetime:BAAALgAECgEJAQAAAA==.Spooñ:BAAALgADCgcJBwABLgAFFAUJFgAhAEocAA==.Spottedcoat:BAABLgAECn8qAAIGAAkJhANnfADDAAAGAAkJhANnfADDAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgABLgAFFAQJBQAHAOAHAA==.Stasia:BAAALgADCgkJCQAAAA==.Strangerx:BAAALgAECgEJAgAAAA==.Stregnor:BAABLgAECn88AAIHAAkJBBh5JQBMAgAHAAkJBBh5JQBMAgAAAA==.Styggi:BAAALgAECgQJBgAAAA==.Styggian:BAAALgAECggJCgAAAA==.Styggie:BAAALgAECgEJAQAAAA==.Stygy:BAAALgAECgMJBAAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgAOAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn9DAAMfAAgJehi0GQDjAQAfAAgJehi0GQDjAQAcAAUJsQ7PUQC8AAAAAA==.',
Sv='Svéria:BAAALgADCgcJCgAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMoAAkJDxKrEwBHAgAoAAkJfhGrEwBHAgAlAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgkJJgAoAB4bAA==.Tachie:BAABLgAECn8mAAMoAAkJHhtEDwByAgAoAAkJuBpEDwByAgAlAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAcJHwALAE4lAA==.Taele:BAABLgAECn8tAAMKAAkJTxzKJwB7AgAKAAkJtBvKJwB7AgAjAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn9gAAIUAAkJSBsEAgB0AgAUAAkJSBsEAgB0AgAAAA==.Tamalpais:BAABLgAECn8dAAIHAAUJZhHyLQCbAAAHAAUJZhHyLQCbAAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJMAARANUgAA==.Tamzred:BAAALgAECgYJBgABLgAECgkJKQAEAM8VAA==.Tanyab:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgAECgEJAQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8qAAIHAAkJWgUILwCWAAAHAAkJWgUILwCWAAAAAA==.',
Th='Thaesan:BAAALgAECgYJDwAAAA==.Therin:BAABLgAECn8+AAIdAAkJwBiTAgDBAQAdAAkJwBiTAgDBAQAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tillymonick:BAAALgAECgUJCAAAAA==.Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgcJHAAAAA==.Toofast:BAABLgAECn9JAAIQAAkJfiKzCgALAwAQAAkJfiKzCgALAwAAAA==.Toofurrious:BAAALgADCgkJQAAAAA==.Tooghast:BAAALgADCgcJDQAAAA==.Topswimmer:BAACLgAFFH8MAAIKAAIJthL+UwCIAAAKAAIJthL+UwCIAAAuAAQKfxkAAgoABwlSFsxsAKEBAAoABwlSFsxsAKEBAAAA.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Traci:BAABLgAECn8jAAIiAAgJyxUBGACRAQAiAAgJyxUBGACRAQAAAA==.Tractor:BAAALgAECggJBgAAAA==.Trifus:BAABLgAECn8pAAMSAAkJ6hg4GACiAQASAAgJlRc4GACiAQAYAAcJ0w84ZACfAQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8hAAIGAAYJHR5TKgADAgAGAAYJHR5TKgADAgAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgQJBgAPAAAAAA==.',
Tu='Tulao:BAABLgAECn84AAIKAAkJtSAVBQBvAgAKAAkJtSAVBQBvAgAAAA==.',
Tw='Twan:BAAALgAFFAEJAgABLgAFFAgJFQAeAAUVAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCgAAAA==.',
Tz='Tzitzimitl:BAAALgAECgYJBwAAAA==.',
['Tà']='Tàkhisis:BAAALgADCgUJBQAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIhAAQJaRDxNADXAAAhAAQJaRDxNADXAAAAAA==.',
Ut='Utheli:BAACLgAFFH8XAAIEAAUJqRMfQwAlAQAEAAUJqRMfQwAlAQAuAAQKfx8AAgQACAkBG95MAOABAAQACAkBG95MAOABAAAA.',
Va='Vaevictis:BAABLgAECn8aAAIVAAgJfRwBAQCjAgAVAAgJfRwBAQCjAgAAAA==.Vaildora:BAAALgAECgEJAQABLgAECgkJJgAoAB4bAA==.Valdra:BAABLgAECn89AAICAAkJGRPtEgC9AQACAAkJGRPtEgC9AQAAAA==.Valkyl:BAAALgAECgEJAQAAAA==.Valkylpriest:BAAALgAECgEJAgAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJDwAAAA==.Virelia:BAAALgAECgEJAQAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8hAAMeAAkJbxFWUACVAQAeAAkJbxFWUACVAQAOAAYJEg7zNADrAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8QAAIEAAYJ+gwIUgALAQAEAAYJ+gwIUgALAQAuAAQKfywAAgQACQkrICkKAD8DAAQACQkrICkKAD8DAAAA.',
Vo='Vogue:BAAALgADCgcJBQAAAA==.',
Vr='Vrale:BAAALgAFFAIJAgAAAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Wes:BAAALgAECgEJAQAAAA==.Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wildbear:BAAALgAECgYJBgAAAA==.Wilken:BAABLgAECn84AAIgAAkJ0BviCABjAgAgAAkJ0BviCABjAgAAAA==.Windria:BAAALgAECgMJAwAAAA==.',
Wo='Wobblenozzle:BAAALgAECgEJAQAAAA==.Wolves:BAAALgAECgIJAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8pAAIEAAkJ/xp6MQA6AgAEAAkJ/xp6MQA6AgAAAA==.',
Ws='Wspr:BAAALgAECgIJBgAAAA==.',
Wu='Wulff:BAAALgADCgMJBgAAAA==.',
Xa='Xaartahli:BAAALgAECgUJEAAAAA==.Xavencia:BAABLgAECn8XAAIKAAkJjQYwGAAYAQAKAAkJjQYwGAAYAQAAAA==.Xavienz:BAAALgAECgEJAQAAAA==.',
Xe='Xenolithia:BAAALgAECgQJBQAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECggJCwAAAA==.',
Ya='Yanut:BAABLgAECn8UAAIEAAYJqQdC7ADPAAAEAAYJqQdC7ADPAAAAAA==.',
Ye='Yeetjin:BAAALgAECggJCwAAAA==.',
Yi='Yinamin:BAABLgAECn8UAAIIAAYJlQtjTQDaAAAIAAYJlQtjTQDaAAAAAA==.',
Yk='Yknub:BAAALgAECgQJBAAAAA==.',
Yo='Yotin:BAAALgAECgYJBgAAAA==.',
Ys='Ysabéll:BAAALgADCgYJDAAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8jAAIGAAkJZhT5JQAeAgAGAAkJZhT5JQAeAgAAAA==.Zalanto:BAAALgAECgMJBgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn9lAAIHAAkJYRcTBwAlAgAHAAkJYRcTBwAlAgAAAA==.',
Ze='Zedator:BAAALgADCgMJAwAAAA==.Zedraikis:BAAALgAECgEJAQAAAA==.Zelgaddis:BAABLgAECn8sAAMQAAkJ6xM6CQCsAQAQAAkJ6xM6CQCsAQARAAIJTQSwQQAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn83AAIoAAkJCRWuAgDCAQAoAAkJCRWuAgDCAQAAAA==.',
Zr='Zrathan:BAEALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Zriana:BAAALgAECgQJCAAAAA==.',
Zs='Zsarilya:BAABLgAECn8uAAINAAkJMAOfEQCJAAANAAkJMAOfEQCJAAAAAA==.',
Zu='Zurgen:BAABLgAECn89AAIXAAkJiyDrDADmAgAXAAkJiyDrDADmAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Àn']='Àndrol:BAAALgAECgQJBwABLgAFFAgJFgAeACQQAA==.',
['Åw']='Åwesomesauce:BAAALgAECgYJBwAAAA==.',
['Êc']='Êclipse:BAEBLgAECn9IAAMGAAkJNiBaAQD2AgAGAAkJNiBaAQD2AgAUAAEJbA75JwAsAAABLgAFFAUJHQANAKsQAA==.',
['Ýu']='Ýui:BAAALgADCgQJBAAAAA==.',
['ßo']='ßooßear:BAAALgAECgMJBQAAAA==.',
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
