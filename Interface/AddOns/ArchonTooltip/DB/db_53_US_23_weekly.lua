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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Mage-Fire','Paladin-Protection','Warrior-Arms','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement','DemonHunter-Devourer','Mage-Arcane','Warrior-Protection','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warlock-Destruction','Mage-Frost','Paladin-Retribution','Rogue-Subtlety','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Evoker-Preservation','Hunter-Survival','Paladin-Holy','Evoker-Devastation','Warlock-Affliction','Druid-Guardian','Warlock-Demonology','Hunter-Marksmanship','Priest-Discipline','Warrior-Fury','Druid-Balance','Druid-Restoration','Druid-Feral',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaradh:BAABNQAECn8lAAMBAAoKbgi+FwA0AQABAAoKbgi+FwA0AQACAAEKqQOpnwAfAAAAAA==.Aaradk:BAABNQAECn8mAAMDAAoKHw1pWACRAQADAAoKHw1pWACRAQAEAAEKRQOx+AAfAAABNQAECgoKJQABAG4IAA==.Aarahunt:BAAANQAECgYICgABNQAECgoKJQABAG4IAA==.',
Ab='Abaddondk:BAABNQAECn8wAAIFAAkKXBQHNQDPAQAFAAkKXBQHNQDPAQAAAA==.Abilify:BAAANQABCgcIJgAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Aces:BAABNQAECn8bAAMGAAkK4QpigAAQAQAGAAkK4QpigAAQAQAHAAgKuAYntgABAQAAAA==.Acez:BAAANQAECggIEAABNQAECgkJGwAGAOEKAA==.Acidwaste:BAAANQADCggIHAAAAA==.',
Ad='Addilynn:BAABNQAECn8YAAICAAUKpAEBggBvAAACAAUKpAEBggBvAAAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAABNQAECn8+AAIIAAoKmhW3AQCBAgAIAAoKmhW3AQCBAgAAAA==.',
Ae='Aelania:BAABNQAECn8bAAIJAAgKUBGnKAAuAQAJAAgKUBGnKAAuAQAAAA==.Aelunara:BAABNQAECn8mAAMEAAkKJRm/VAC/AQAEAAkKJRm/VAC/AQADAAEKAABzzgAvAAAAAA==.Aemoz:BAAANQAECgQJBAAAAA==.Aerthalis:BAAANQADCgIIAgAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgYIDQAAAA==.',
Ai='Ailric:BAAANQAECgYIDgAAAA==.Ainke:BAAANQADCgYIDgAAAA==.',
Al='Alarakian:BAABNQAECn8pAAIKAAoKVhrMKgCUAgAKAAoKVhrMKgCUAgAAAA==.Alassae:BAAANQAECgYIBgAAAA==.Alexei:BAABNQAECn82AAMLAAkKRRjvGADqAQALAAkKRRjvGADqAQAMAAcK1A1THQATAQAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAABNQAECn8gAAQGAAoKoA08cgDKAQAGAAkK5ws8cgDKAQAHAAUKehD7qwAZAQANAAIK3QP6MQBWAAAAAA==.Alkhan:BAABNQAECn8rAAMCAAkK0QfkRwAOAQACAAgKYQjkRwAOAQAOAAEKbgTtWwAmAAABNQAFFAQIBQAPAPQGAA==.Allymage:BAAANQADCgMIAwAAAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altheaz:BAAANQAECgIIAgAAAA==.Altoids:BAAANQAECgUIDAAAAA==.Altos:BAACNQAFFH8PAAMQAAUK/gRHBQCLAAAQAAQK/gRHBQCLAAAKAAIKAADaOwAAAAA1AAQKf04AAhAACgrgFkYNAOsBABAACgrgFkYNAOsBAAAA.Altóids:BAAANQAECgQIBAABNQAECgUIDAARAAAAAA==.Alwayshazy:BAAANQADCgUIBQAAAA==.Alyssachik:BAAANQAECgcIDgAAAA==.',
Am='Amdabear:BAAANQADCgcIDAAAAA==.Ampreistguy:BAAANQADCgYIBgABNQAECgoKLQAHAMgkAA==.',
An='Anartik:BAABNQAECn8aAAIPAAoKbgf+nABrAQAPAAoKbgf+nABrAQAAAA==.Anavar:BAAANQADCgYIDwAAAA==.Angerclaw:BAAANQAECgcIDAAAAA==.Animeow:BAABNQAECn8uAAMSAAkKGSCjFAAyAwASAAkKGSCjFAAyAwATAAMKhSOlOADVAAAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.Annaalista:BAAANQABCgcIFAAAAA==.Annasun:BAAANQADCgUIBQABNQAECggIJAAUABkSAA==.',
Ap='Aplpiemonday:BAAANQADCgcIBwAAAA==.Apoth:BAAANQAECgcICAABNQAECggIDgARAAAAAA==.Apothe:BAAANQAECgUIBQABNQAECggIDgARAAAAAA==.Apotheke:BAAANQAECggIDgAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQAECgEIAQAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAABNQAECn8lAAIPAAkK/BXitwAUAgAPAAkK/BXitwAUAgAAAA==.Arcanofrosty:BAABNQAECn8dAAMVAAcKmAXqJwChAAAPAAYK0QHjggG+AAAVAAYKSQbqJwChAAAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.Arwen:BAAANQABCgIIBAAAAA==.',
At='Atalmon:BAABNQAECn8+AAIWAAoKihotTwA+AgAWAAoKihotTwA+AgAAAA==.',
Au='Aurochi:BAAANQAECgMIBQAAAA==.',
Av='Avastin:BAAANQAECgEIAQAAAA==.',
Aw='Awni:BAABNQAECn8xAAIKAAkKYxY2eAAuAgAKAAkKYxY2eAAuAgAAAA==.',
Ba='Bacon:BAABNQAECn88AAITAAoK1A63JAAKAgATAAoK1A63JAAKAgAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAABNQAECn8iAAIPAAkK+B/4YwDuAQAPAAkK+B/4YwDuAQAAAA==.Baknow:BAAANQAECgIIAwAAAA==.Bambuu:BAAANQABCggIDAAAAA==.Bangbangji:BAABNQAECn8VAAIKAAgKihB0bAC8AQAKAAgKihB0bAC8AQABNQAECgoKUAAXAOkhAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAABNQAECn8fAAIPAAgKUQyesABDAQAPAAgKUQyesABDAQAAAA==.Bartholomeow:BAAANQADCgQIBAAAAA==.Basch:BAAANQABCgYIDAAAAA==.Battlebeats:BAAANQAECgUIBQAAAA==.Bazzoo:BAAANQAECggIDQAAAA==.',
Be='Beachbabe:BAAANQADCgcIBwAAAA==.Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAABNQAECn82AAIYAAoKRB0ANgDJAgAYAAoKRB0ANgDJAgAAAA==.Beeloved:BAAANQADCgYIBgAAAA==.Benzos:BAACNQAFFH8FAAQXAAQK6g3QHACaAAAXAAIK/grQHACaAAAZAAIKxBOkHgBNAAAaAAEK7QvyAwBCAAA1AAQKfzMABBkACgquJHwLAC0DABkACQqaJHwLAC0DABoACApAIaIEAL8CABcAAgrlJV69AHEAAAAA.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bethezar:BAAANQAECgcICgAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAABNQAECn8/AAIbAAoKyxpBDgCfAgAbAAoKyxpBDgCfAgAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgUIDgAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQAECgUIEQAAAA==.',
Bl='Bluerose:BAABNQAECn8VAAIYAAUKxgf4/gAHAQAYAAUKxgf4/gAHAQAAAA==.Blurry:BAABNQAECn8kAAIUAAgKGRIZDAA2AgAUAAgKGRIZDAA2AgAAAA==.',
Bo='Boltsandhoes:BAAANQADCggICAABNQAECgcIEQARAAAAAA==.Boomidk:BAAANQAECgMIAwAAAA==.Bountmage:BAABNQAECn8uAAMVAAkKpxYsCwDuAQAVAAkKpxYsCwDuAQAPAAEKAACgfQEAAAAAAA==.Bovinnie:BAAANQAECgMIAwAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brainn:BAAANQADCgUIBQAAAA==.Brillectra:BAAANQAECgMIAQAAAA==.Brisketboy:BAAANQADCgQIBAAAAA==.Bro:BAAANQAECgUIDgAAAA==.Brokentuskz:BAAANQAECggJAQABNQAECgkJMAAFAFwUAA==.Bronthos:BAAANQADCggICAAAAA==.Brothertunks:BAAANQADCgMIAwAAAA==.Brêwski:BAAANQAECgIIAgAAAA==.',
Bu='Budago:BAABNQAECn8aAAITAAgKOw7rIwBmAQATAAgKOw7rIwBmAQAAAA==.Buffbutton:BAABNQAECn8zAAIPAAoKsA2hZgDnAQAPAAoKsA2hZgDnAQABNQAECgoKVwAKAD4cAA==.Buffstallion:BAAANQAECgQIBwAAAA==.Buzzie:BAAANQADCggIFAAAAA==.',
['Bï']='Bïllï:BAACNQAFFH8FAAIGAAIK7RQnHQCQAAAGAAIK7RQnHQCQAAA1AAQKfy4AAgYACgr2H34ZADADAAYACgr2H34ZADADAAAA.',
Ca='Caerisma:BAAANQAECggILAAAAQ==.Cakevswaffle:BAAANQAECggIAQAAAA==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Celestino:BAAANQAECgUIBQAAAA==.Cellica:BAAANQAECgQICAAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Chainevoker:BAAANQAECgcIDAAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQAECggIEAABNQAECggILAARAAAAAQ==.Chasity:BAAANQADCgQIBAAAAA==.Chiang:BAAANQAECggIDAAAAA==.Chilijayleen:BAAANQAECggIDgABNQAECgoKLwAYAHYSAA==.Chlena:BAABNQAECn8eAAIcAAkK6STeAQDFAwAcAAkK6STeAQDFAwAAAA==.Chlori:BAAANQAECgUIBQABNQAECgkJHwAdAAkXAA==.Chudmax:BAAANQADCgYIDQAAAA==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUJBgAAAA==.',
Cl='Clegen:BAAANQADCggIDQAAAA==.Cloax:BAACNQAFFH8MAAITAAQKVxUeCgDwAAATAAQKVxUeCgDwAAA1AAQKf04AAhMACgrOIW4GAAoDABMACgrOIW4GAAoDAAAA.Cláp:BAABNQAFFH8HAAIQAAcK6xUxAQDrAQAQAAcK6xUxAQDrAQAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAEANQADCggIDgABNQAECgoKLQAXADkQAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Conquerlock:BAAANQAECgMIAwAAAA==.Coobibrains:BAAANQADCgUIBwAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCggIDQAAAA==.Cory:BAAANQADCgMIAwAAAA==.Cosétte:BAAANQAECgUIBQABNQAECgkJIgAHACQeAA==.Cowchipp:BAAANQADCgUICgAAAA==.',
Cr='Craerman:BAAANQADCgYICwABNQAECggILAARAAAAAQ==.Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Creella:BAAANQADCgUIBgAAAA==.Crewbin:BAAANQADCggICAAAAA==.Croobin:BAAANQADCggICAAAAA==.Cryhavok:BAACNQAFFH8MAAMWAAQKABJGFwDTAAAWAAMKABJGFwDTAAAeAAIK0gI3KgA9AAA1AAQKf0cAAxYACgo8Hbg/AGsCABYACgo8Hbg/AGsCAB4AAgquDsIAAXkAAAAA.',
Cu='Cussack:BAABNQAECn8uAAIKAAoKyiLyHABEAwAKAAoKyiLyHABEAwAAAA==.Cutepandaa:BAAANQADCgQIBAAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgoKUAAXAOkhAA==.Daghar:BAAANQAECgIJAwAAAA==.Dagoatfr:BAAANQADCggIFQAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAABNQAECn8pAAIKAAoKaw0WZADUAQAKAAoKaw0WZADUAQABNQAECggIGgATADsOAA==.Danui:BAAANQADCgQIBAAAAA==.Danuth:BAAANQADCgUIBQAAAA==.Darkgol:BAABNQAECn8sAAIKAAkK/gwvawDAAQAKAAkK/gwvawDAAQABNQAECgoKMAAWAEMSAA==.Darkshammys:BAAANQAECgEIAQAAAA==.Darkshayd:BAAANQADCgIIAgAAAA==.Davioon:BAAANQAECgIIBQAAAA==.Dayrb:BAAANQAECgYIDQAAAA==.',
Db='Dblade:BAAANQAFFAQIBAAAAA==.',
De='Deadlyheal:BAAANQAECggIDwABNQADCggICAARAAAAAA==.Deadtalini:BAACNQAFFH8KAAMDAAUKxA1tGgCcAAADAAUKjg1tGgCcAAAFAAIKiwm9GQBvAAA1AAQKf0AAAwUACgpjH3oYAMYCAAUACgpmGnoYAMYCAAMACgpqGws5ACICAAAA.Deah:BAABNQAECn8tAAIYAAkKbCJeDQAkAwAYAAkKbCJeDQAkAwAAAA==.Deathstarr:BAAANQADCggIDQAAAA==.Deaththroes:BAAANQAECgQIBQAAAA==.Deckerdramon:BAABNQAECn86AAIQAAoKjxp5CQC0AgAQAAoKjxp5CQC0AgAAAA==.Demomachin:BAABNQAECn82AAIBAAoKeRrNBwAJAgABAAoKeRrNBwAJAgAAAA==.Demonnoodle:BAAANQADCggICQABNQAECgcIFwAIAKwQAA==.Demonsfear:BAABNQAECn8yAAIOAAoKThvMGQCLAgAOAAoKThvMGQCLAgAAAA==.Demyze:BAAANQADCggIEAAAAA==.Denorak:BAAANQAECgUICgAAAA==.Densetsu:BAAANQADCgcJBwAAAA==.Destroyera:BAAANQAECgcIBwAAAA==.Deucalyon:BAAANQADCggIJAAAAA==.Devanaa:BAAANQADCgYIBgAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devourme:BAAANQAECgIIAgABNQAFFAcIGgAHAKsZAA==.Devours:BAACNQAFFH8aAAIHAAcKqxk6CwCZAQAHAAcKqxk6CwCZAQA1AAQKfywAAgcACgriHPgvAKICAAcACgriHPgvAKICAAAA.Devuledegg:BAAANQADCgEIAQAAAA==.',
Di='Dirtyhooves:BAAANQADCggIDwABNQAECgMIBAARAAAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAACNQAFFH8aAAIbAAgK+yOtAACOAgAbAAgK+yOtAACOAgA1AAQKfzUAAhsACgr0JiIAAAEEABsACgr0JiIAAAEEAAAA.',
Do='Doesdrool:BAAANQADCgEIAQAAAA==.Dohtem:BAAANQADCgYICwABNQAECgkJIwANAM4cAA==.Donmegah:BAAANQAECgUIDgAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.Downkid:BAAANQAECgIIAgAAAA==.',
Dr='Draemon:BAAANQADCgEIAQAAAA==.Dragapult:BAABNQAECn8mAAIfAAoK4hrYBACCAgAfAAoK4hrYBACCAgABNQAFFAQIDwADAA4lAA==.Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Dragusysmash:BAAANQAECgIIAQAAAA==.Draki:BAAANQADCgYIEAAAAA==.Drazzin:BAAANQADCgEIAQABNQAECgoKKAAgAKkQAA==.Dredtotem:BAAANQAECgUICQAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Durzaxda:BAAANQAECgEIAQAAAA==.Dusky:BAAANQABCgYICgAAAA==.Dutanu:BAAANQAECgUICQABNQAECgkJOQAWACcfAA==.',
['Dö']='Dötcom:BAAANQADCgYIDAAAAA==.',
Ec='Echpochmak:BAABNQAECn8cAAISAAkK3SPsEQBKAwASAAkK3SPsEQBKAwAAAA==.',
Ei='Eibhlean:BAABNQAECn8wAAIJAAkKhRReHwBzAQAJAAkKhRReHwBzAQABNQAECgQICQARAAAAAA==.Eireckt:BAAANQADCgcIDAAAAA==.Eirrin:BAAANQAFFAEIAQAAAA==.Eivorr:BAAANQABCgQJAgAAAA==.',
El='Elariin:BAABNQAECn8gAAMHAAgK9xvSawDIAQAHAAcK7BvSawDIAQAGAAQKGgwLuACZAAAAAA==.Elaril:BAAANQADCggIIAAAAA==.Eleforever:BAACNQAFFH8FAAIGAAIK4BpAIQCoAAAGAAIK4BpAIQCoAAA1AAQKfz4AAgYACgpWIv4VAEUDAAYACgpWIv4VAEUDAAAA.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcIBwAAAA==.Elleredreaux:BAAANQAECggICgAAAA==.',
Em='Emongar:BAAANQAECgQIBQAAAA==.',
En='Endomorphism:BAAANQAECgIIAgABNQAFFAgIGgAhACghAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ev='Eveldumboone:BAAANQAECgIIAgABNQAFFAYIEwAhAEEdAA==.Evlynia:BAAANQADCgMIAgAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAABNQAECn8vAAIiAAoKeQ+JgADlAQAiAAoKeQ+JgADlAQAAAA==.',
Fa='Fableshoot:BAAANQAECgYICgAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgARAAAAAA==.Fangtang:BAAANQAECggICAAAAA==.Fantasie:BAAANQAECgEIAQABNQAECgoKUAASAEolAA==.Fatherclutch:BAAANQAECgQIBAABNQAECggIHAAMANAMAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAACNQAFFH8JAAIYAAQKZw69FgDdAAAYAAQKZw69FgDdAAA1AAQKf0gAAxgACgpeIN4hALgCABgACgpeIN4hALgCACMAAwreCCNnAI8AAAAA.',
Fe='Fearfactor:BAAANQADCgQIBAAAAA==.Felpal:BAAANQABCgMIAQABNQAECgYIHgAfAFQLAA==.Felwoof:BAABNQAECn87AAQUAAoKTiHvCwACAQAiAAUKTB7RmgCkAQAgAAcKXCG/CwCHAQAUAAMKPB7vCwACAQAAAA==.Felzak:BAAANQADCgYIBgABNQAECgUIDwARAAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgcIFwAAAA==.Fistachio:BAAANQADCggIEgAAAA==.',
Fl='Flarllek:BAAANQADCgYIFAAAAA==.Flexxed:BAABNQAECn8jAAIFAAkKhyHgFgDUAgAFAAkKhyHgFgDUAgAAAA==.Floorlock:BAAANQADCgUIBQAAAA==.Florin:BAAANQAECgIIBQAAAA==.',
Fo='Foopz:BAAANQADCgIJAgABNQAECgEIAgARAAAAAA==.Forthehordde:BAAANQABCgcICwAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Freddybones:BAAANQAECgEIAgAAAA==.Friendlytwo:BAAANQADCggIDgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgUICwABNQAECgoKUAASAEolAA==.Frostyduggo:BAABNQAECn82AAIVAAoKjwvMDwCSAQAVAAoKjwvMDwCSAQAAAA==.Frostyxz:BAAANQADCgQIBAAAAA==.Fry:BAACNQAFFH8ZAAITAAgK/BF3BQDgAQATAAgK/BF3BQDgAQA1AAQKfywAAhMACgp5H5QWAKcCABMACgp5H5QWAKcCAAAA.Fríeren:BAAANQADCgIIAgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgYIEAAAAA==.Fumblemore:BAAANQADCgEIAQAAAA==.Furystrike:BAABNQAECn8vAAMQAAkK9CRkBgAAAwAQAAkK5SJkBgAAAwAKAAkKzh/GQwC+AgAAAA==.Futbuckmcgee:BAAANQADCggICAAAAA==.Fuupa:BAAANQADCgIIAgABNQAECgEIAgARAAAAAA==.',
Ga='Galixie:BAAANQABCgQIBgAAAA==.Ganondrow:BAABNQAECn82AAQTAAoKkCLkCgCvAgATAAoKkCLkCgCvAgASAAMKqhrmtAD4AAAkAAEKng6XJgA8AAAAAA==.',
Ge='Gehagnute:BAAANQADCgEIAQAAAA==.Gemelo:BAABNQAECn8nAAIdAAoKHhWpBQAAAgAdAAoKHhWpBQAAAgAAAA==.Geromul:BAAANQAECgYIBwAAAA==.Gerrexs:BAABNQAECn8VAAIKAAgKOhA9swCdAQAKAAgKOhA9swCdAQAAAA==.',
Gi='Gibayy:BAABNQAECn8YAAIPAAcKcx6psgAeAgAPAAcKcx6psgAeAgAAAA==.Gibsonex:BAAANQAECgYIDAAAAA==.Gideone:BAAANQADCgYICgAAAA==.Gildagni:BAAANQAECgQIBAAAAA==.Gilliamm:BAABNQAECn9GAAMXAAoKXxgOMwAvAgAXAAkKmhoOMwAvAgAZAAUKWxJrWgBPAQAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Gn='Gnorman:BAAANQADCgIIAgAAAA==.',
Go='Golath:BAABNQAECn8wAAIWAAoKQxLxjACyAQAWAAoKQxLxjACyAQAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAABNQAECn8jAAIYAAkK6ARKvQA3AQAYAAkK6ARKvQA3AQAAAA==.Gothbutta:BAAANQAECgQICgAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Grandena:BAAANQADCgUICgAAAA==.Graydeon:BAAANQAECggIEQAAAA==.Greatangel:BAAANQADCgUIBAABNQAECggIJAAUABkSAA==.Gregano:BAAANQAECgUIBAABNQAECgkJHgAKACkMAA==.Gregorian:BAABNQAECn8eAAIKAAkKKQwBqQC2AQAKAAkKKQwBqQC2AQAAAA==.Gremliin:BAACNQAFFH8SAAISAAUK+hRMEwB2AQASAAUK+hRMEwB2AQA1AAQKfz0AAhIACgq8HnoWAB8DABIACgq8HnoWAB8DAAAA.Gremliinss:BAAANQAECgcIBwAAAA==.Gretch:BAAANQAECgYICwAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Gu='Gunnerbe:BAAANQADCgYICQAAAA==.',
Ha='Hadesdecends:BAAANQADCgMIAwAAAA==.Halakal:BAAANQAECgUIDwAAAA==.Halparogue:BAAANQADCgIIAgAAAA==.Hammerbell:BAAANQAECggJCAAAAA==.Haviboomer:BAAANQAECgQICAAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.',
He='Healmeharder:BAAANQADCgIIAgAAAA==.Healminth:BAAANQAFFAQIAgAAAA==.Healthcare:BAAANQAECgcICQAAAA==.Healuminati:BAAANQAECgYIBgAAAA==.Herbatron:BAAANQAECgEIAQAAAA==.Hethar:BAAANQAECgEIAQAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hightide:BAAANQAECggIEgAAAA==.Hilltop:BAAANQABCgEIAQAAAA==.Hippo:BAAANQAECgYIEAAAAA==.',
Ho='Hoja:BAABNQAECn8eAAMHAAoK1hXlNgA+AgAHAAkKERblNgA+AgAGAAIKnAaIHQFVAAAAAA==.Holdor:BAAANQADCgUIBgAAAA==.Holdors:BAAANQADCggIDAAAAA==.Holier:BAAANQADCgYIBgABNQADCggJCAARAAAAAA==.Holybloodboi:BAAANQAECgEJAQABNQAECgoKLQAHAMgkAA==.Holybuns:BAAANQAECgIIAgAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIBQABNQAECgcIFwAIAKwQAA==.Holyzeus:BAAANQAFFAEIAQAAAA==.',
Ht='Htilogak:BAAANQAECgMIAwAAAA==.',
Hu='Hunglikabull:BAAANQAECgUIBQAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAABNQAECgYIBwARAAAAAA==.',
Ic='Iceangell:BAAANQAECgcIDAAAAA==.Iceberg:BAAANQADCgYIBgAAAA==.Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQAECgMIAwAAAA==.',
In='Insanegrippy:BAABNQAECn8UAAIDAAkKvBnvHQANAgADAAkKvBnvHQANAgABNQAFFAgIHgAHAHsaAA==.Intaria:BAACNQAFFH8IAAIKAAMKugPuJwCRAAAKAAMKugPuJwCRAAA1AAQKfy4AAwoACgqVFSl0ADgCAAoACgpgFSl0ADgCACUAAwpDFHoiAKMAAAAA.Invisibulity:BAAANQADCgYICQABNQAECgYIHgAfAFQLAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgMIAgAAAA==.Itsrambo:BAABNQAECn8rAAIWAAoK/BkMTwA+AgAWAAoK/BkMTwA+AgAAAA==.',
Ja='Jackbeef:BAACNQAFFH8HAAIlAAIKLBqJAgCNAAAlAAIKLBqJAgCNAAA1AAQKf0IAAiUACgoFJcUAAGIDACUACgoFJcUAAGIDAAAA.Jadedhooves:BAABNQAECn8rAAIWAAcKiRCj4wBUAQAWAAcKiRCj4wBUAQAAAA==.Jaggedlilhun:BAABNQAECn8vAAIYAAoKdhJudADWAQAYAAoKdhJudADWAQAAAA==.Jaggedshammy:BAABNQAECn8cAAIGAAgKXQm5ZwBQAQAGAAgKXQm5ZwBQAQABNQAECgoKLwAYAHYSAA==.Jagruk:BAAANQADCgIIAgABNQAECgUIDwARAAAAAA==.Jak:BAAANQADCgUIBQAAAA==.Janwalutala:BAAANQADCgYIBgAAAA==.Jareyk:BAABNQAECn8+AAMeAAoKvRzfQgBZAgAeAAoKvRzfQgBZAgAWAAEKAADO1AEAAAAAAA==.Jarladorin:BAAANQAECgIIAwABNQAECgoKJgAKAMoPAA==.Jarlu:BAAANQAECggICgAAAA==.Jaxodk:BAABNQAECn8mAAMEAAkK+CEdFgAKAwAEAAgKqiIdFgAKAwAFAAkKlR4eIQCEAgAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jecka:BAAANQAECgEIAgAAAA==.Jecynth:BAAANQADCggIEgAAAA==.Jedai:BAACNQAFFH8RAAIeAAUK8RP+DQBnAQAeAAUK8RP+DQBnAQA1AAQKf0kAAh4ACgrIIsELAG0DAB4ACgrIIsELAG0DAAAA.Jellybeann:BAAANQADCgUIEQAAAA==.Jerryfour:BAAANQAECgMIAwAAAA==.Jerrysix:BAABNQAECn8sAAMTAAkK0hOlKQDbAQATAAgK/hSlKQDbAQAkAAkKTRW3BQCpAQAAAA==.Jerrytwo:BAAANQAECgQIBgAAAA==.',
Ji='Jilseponie:BAAANQABCgIIAgABNQAECgkJFAALAI0LAA==.Jimmypop:BAAANQAECgQIBAAAAA==.',
Ju='Judadiah:BAABNQAECn8mAAIKAAoKyg8ybAC9AQAKAAoKyg8ybAC9AQAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgUIBwAAAA==.',
['Jà']='Jàxx:BAABNQAECn8iAAIHAAkKJB6oLwBiAgAHAAkKJB6oLwBiAgAAAA==.',
['Jä']='Jänice:BAAANQAECggIAQAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECgoKLwAYAHYSAA==.',
Ka='Kaanha:BAAANQADCgEIAQAAAA==.Kaego:BAAANQAECgEIAQABNQAECgoKOQAmAMEWAA==.Kalinzern:BAAANQADCgEIAQAAAA==.Kalona:BAAANQADCgUICQAAAA==.Kalrock:BAABNQAECn8YAAMiAAkKeBfsiADQAQAiAAgKjhfsiADQAQAUAAEK8hbKcAA+AAAAAA==.Kalrotten:BAAANQADCgcICgABNQAECgkJGAAiAHgXAA==.Kalulu:BAAANQADCggIGQAAAA==.Kalyssi:BAAANQAECgQIBgAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Kanhwa:BAAANQADCgIIAgAAAA==.Kareir:BAAANQADCgUIBQAAAA==.Karkit:BAAANQAECgUIDgAAAA==.Katigotbandz:BAABNQAECn8dAAIWAAkKZBjAbAD2AQAWAAkKZBjAbAD2AQAAAA==.Katkot:BAABNQAECn8jAAIWAAoK7BaKlQD4AQAWAAoK7BaKlQD4AQAAAA==.Kayro:BAAANQADCgUICAAAAA==.Kazalandera:BAAANQADCgQICAAAAA==.Kazlan:BAAANQAECgQIBwAAAA==.Kazplan:BAAANQAECgUIBQAAAA==.Kazzulee:BAAANQADCgEIAQAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.Kepchuk:BAABNQAECn8mAAIcAAkKdyQeAgC2AwAcAAkKdyQeAgC2AwAAAA==.Keres:BAACNQAFFH8PAAIDAAQKDiUJDQCDAQADAAQKDiUJDQCDAQA1AAQKfy4AAgMACgqcJI0HAIIDAAMACgqcJI0HAIIDAAAA.Keselip:BAAANQAECgYIBwAAAA==.',
Kh='Khagolith:BAABNQAECn85AAImAAoKwRYeKgCvAQAmAAoKwRYeKgCvAQAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.Kirstinn:BAAANQAECgYICQAAAA==.Kizzazz:BAAANQADCgUICAAAAA==.',
Kk='Kkodabear:BAAANQAECgIIBAAAAA==.',
Kl='Klixeas:BAABNQAECn8WAAIeAAcKrw9wcQBgAQAeAAcKrw9wcQBgAQAAAA==.',
Kn='Knïghtshädë:BAAANQADCgUIBQAAAA==.',
Ko='Kobiter:BAABNQAECn8qAAQWAAkKRRWJnADpAQAWAAkKHBWJnADpAQAeAAgKjwz2egCoAQAJAAUKuA5KTwCqAAABNQAFFAQICAAQAOMYAA==.Kobito:BAACNQAFFH8IAAIQAAQK4xg+AwDZAAAQAAQK4xg+AwDZAAA1AAQKf00AAxAACgpUI/MCAHoDABAACgpUI/MCAHoDAAoABwp0En+eAEEBAAAA.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECn9MAAMYAAoKMiXLBAC/AwAYAAoKMiXLBAC/AwAjAAMKMxBoTQBrAAAAAA==.Koupe:BAABNQAECn84AAMnAAoKaBz8DAD4AgAnAAoKaBz8DAD4AgAmAAUKDhCmbwAMAQABNQAECgoKTAAYADIlAA==.',
Kr='Krang:BAAANQAECggICAAAAA==.Kranx:BAAANQAECgUIAwAAAA==.Krayzebeef:BAAANQAECgQIDwABNQAECgUIDgARAAAAAA==.Kriss:BAABNQAECn8kAAIYAAgKBguvsQBPAQAYAAgKBguvsQBPAQAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgoKTAAYADIlAA==.Kurirne:BAAANQADCgQIBQAAAA==.Kurkanak:BAAANQAECgIIAgAAAA==.',
Ky='Kyewanda:BAAANQAECggIEwAAAA==.Kyusakuu:BAAANQAECgYIDAABNQAFFAUIDQAiAC0gAA==.',
La='Laanu:BAAANQAECgMIAwABNQAECgoKUAAXAM4eAA==.Laci:BAAANQADCggIDgAAAA==.Lagurtalokbr:BAAANQADCgIIAgAAAA==.Lahey:BAACNQAFFH8TAAIKAAUKnBXWGADoAAAKAAUKnBXWGADoAAA1AAQKf0kAAgoACgqDHdhAAEACAAoACgqDHdhAAEACAAAA.Lakes:BAAANQAECgYIDgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lasucia:BAAANQADCggICAAAAA==.Lathara:BAAANQAECgUIDgAAAA==.Laughzfalcon:BAAANQAECgcICwAAAA==.Lavs:BAABNQAECn8kAAIoAAgK1R9sCwAgAgAoAAgK1R9sCwAgAgAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.Layona:BAAANQADCggICAAAAA==.',
Ld='Ldykillshot:BAAANQAECgMIBAAAAA==.',
Le='Legatto:BAAANQADCgIIAgAAAA==.Legiance:BAAANQAECgEIAQAAAA==.Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAABNQAECn8UAAIWAAgKyxKQtQCzAQAWAAgKyxKQtQCzAQAAAA==.Lexiah:BAABNQAECn8iAAMSAAcKaghTowDzAAASAAcKaghTowDzAAATAAEKAAA4kwAVAAAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lilliana:BAAANQAECgEIAQABNQAECgkJIAAPAGQKAA==.Linneasage:BAAANQADCgQIBAAAAA==.Lionofjudah:BAAANQABCgYIDQAAAA==.Litebringa:BAAANQAECgcIBwAAAA==.Lizardbrain:BAAANQAECgMIBwAAAQ==.',
Lo='Loamathor:BAAANQAECggIEgAAAA==.Lockkdown:BAAANQADCgYIBgAAAA==.Loesh:BAAANQADCgIJAgAAAA==.Lohharhuuk:BAAANQADCggICAAAAA==.Lolyoumad:BAABNQAECn8WAAINAAgKeAjYHABOAQANAAgKeAjYHABOAQAAAA==.Lorcat:BAAANQAECgEIAQAAAA==.Lorilyn:BAABNQAECn8uAAISAAgK1R1HPgBBAgASAAgK1R1HPgBBAgAAAA==.Lormuncher:BAAANQAECgQIBgAAAA==.Lorthag:BAABNQAECn9GAAIkAAkKoxM+BAAJAgAkAAkKoxM+BAAJAgAAAA==.Lovebuz:BAAANQAECgQIBAAAAA==.Loveles:BAAANQADCggICAAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCggIDwAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Luki:BAAANQABCggIDwAAAA==.Lulbah:BAABNQAECn8UAAIhAAcK5BtuFQARAgAhAAcK5BtuFQARAgAAAA==.Lunachick:BAAANQAECgQIBQAAAA==.Lunareclips:BAAANQADCgMIBAAAAA==.Lunarus:BAABNQAECn8pAAIgAAgKFQ4RCwC/AQAgAAgKFQ4RCwC/AQAAAA==.Luniare:BAAANQAECgQIBQAAAA==.',
Ly='Lyríc:BAAANQADCgEIAQABNQAECgkJIgAHACQeAA==.',
['Lì']='Lìfe:BAABNQAECn8jAAIKAAgKZxfidgAxAgAKAAgKZxfidgAxAgAAAA==.',
['Ló']='Lónnie:BAAANQAECgMIAwAAAA==.Lónnìe:BAAANQAECgcIEAAAAA==.Lónníe:BAAANQAECgQICQAAAA==.',
Ma='Macloving:BAAANQAECgYIEAAAAA==.Maelona:BAAANQAECggIDAAAAA==.Maen:BAAANQAECgIIBAAAAA==.Magrumok:BAABNQAECn8lAAIEAAoK3xx3GQAcAgAEAAoK3xx3GQAcAgAAAA==.Magthars:BAAANQAECgMIBQAAAA==.Magtide:BAACNQAFFH8LAAIjAAQKFBmXEAAyAQAjAAQKFBmXEAAyAQA1AAQKfxQAAiMACAqMIFsYAJUCACMACAqMIFsYAJUCAAAA.Malväryx:BAABNQAECn80AAIOAAkKPA1PKgBFAQAOAAkKPA1PKgBFAQAAAA==.Manbearpig:BAACNQAFFH8KAAIYAAcKmBB6DACKAQAYAAcKmBB6DACKAQA1AAQKfzsAAhgACgrDIrMVAEUDABgACgrDIrMVAEUDAAAA.Manman:BAAANQAECgMIBAAAAA==.Marqose:BAAANQADCgcIBwABNQAECgUIDwARAAAAAA==.Marshes:BAAANQADCgIIAgABNQAECgYIDgARAAAAAA==.Masshooter:BAAANQAECgEIAQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mcquade:BAAANQABCgIIAgABNQABCgcIBwARAAAAAA==.Mctigly:BAAANQAECgYIEAAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAABNQAECn87AAIPAAoKxBs3dgCRAgAPAAoKxBs3dgCRAgAAAA==.Mellindre:BAAANQAECgQICgAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAABNQAECn8aAAIJAAgKsQygMQBTAQAJAAgKsQygMQBTAQAAAA==.Merlinsmom:BAAANQADCggICAAAAA==.Mesa:BAACNQAFFH8GAAIcAAQKQhYvDAA4AQAcAAQKQhYvDAA4AQA1AAQKf2oCAxwACgrHJgwAABAEABwACgrHJgwAABAEAB8AAQoaEv44AEYAAAAA.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Micaelia:BAAANQAECgQIBAAAAA==.Miclovin:BAABNQAECn8lAAMXAAkKGRipDQCbAgAXAAkKDxipDQCbAgAZAAIKBwVGlwBXAAAAAA==.Microplastic:BAABNQAECn9XAAMKAAoKPhy7MwBwAgAKAAoKPhy7MwBwAgAQAAYK5RNiJwDAAAAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikelmyers:BAABNQAECn8XAAITAAoKpwUVKgA1AQATAAoKpwUVKgA1AQAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAABNQAECn9SAAIEAAoKWRywEQBsAgAEAAoKWRywEQBsAgAAAA==.Minigunn:BAAANQADCggIEAAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQAECgMIAwAAAA==.Misosmol:BAAANQAECgUICwAAAA==.Misowise:BAAANQAECgcIBwAAAA==.Missogyny:BAABNQAECn8kAAIPAAkK0SD8RAD5AgAPAAkK0SD8RAD5AgAAAA==.Miste:BAAANQADCgMIAwAAAA==.Mistie:BAAANQAECgQIBAAAAA==.Mithunzi:BAAANQAECgYIDQAAAA==.',
Mo='Moadeab:BAAANQAECggICwAAAA==.Mogando:BAAANQAECgEIAgABNQAECgoKKAAgAKkQAA==.Mogrodeath:BAAANQAECgUICAABNQAECgoKPwAiAFwgAA==.Mogrodrag:BAAANQADCggICAABNQAECgoKPwAiAFwgAA==.Mogrodruid:BAAANQADCgYIBgABNQAECgoKPwAiAFwgAA==.Mogrogarg:BAABNQAECn8/AAQiAAoKXCAcKwDYAgAiAAoK5h8cKwDYAgAUAAQKah/PDgDcAAAgAAEKvB+XJABcAAAAAA==.Mogrosham:BAAANQAECgcIEgABNQAECgoKPwAiAFwgAA==.Mogrougarg:BAAANQAECgIIAgABNQAECgoKPwAiAFwgAA==.Mojojojò:BAABNQAECn8ZAAMPAAcKBAqlzgAMAQAPAAcKBAqlzgAMAQAVAAMKrQMBMwBuAAAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgoKQwAfACcdAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAFFAIIAgAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQAECgUIBQAAAA==.Moribelar:BAAANQAECgUICAAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAABNQAECn8tAAIYAAoK2iEFEQAMAwAYAAoK2iEFEQAMAwAAAA==.Morventhas:BAAANQADCggICQAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAABNQAECn8fAAIYAAoK9w5ddQDUAQAYAAoK9w5ddQDUAQAAAA==.Mousyz:BAAANQAECgcICAAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Mudflapper:BAAANQAECgQIBAAAAA==.Munric:BAABNQAECn88AAIWAAoKMghaxABLAQAWAAoKMghaxABLAQAAAA==.Munusku:BAABNQAECn8dAAIHAAgKuRB2ZwB/AQAHAAgKuRB2ZwB/AQAAAA==.Murphh:BAAANQAECgYIAwAAAA==.',
My='Myboycleetus:BAAANQAECgUIDAAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.Mystie:BAAANQADCggIEwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQICAAAAA==.',
['Mï']='Mïkasa:BAABNQAECn8fAAIYAAoKEQybhQCuAQAYAAoKEQybhQCuAQAAAA==.',
Na='Nachobussy:BAACNQAFFH8aAAMYAAgKvxgBBwDfAQAYAAcKnhoBBwDfAQAjAAYKUA95DgBWAQA1AAQKfywAAxgACgqtJQESAAcDABgACAohJgESAAcDACMABwoXG7YeAH8BAAAA.Nachothings:BAABNQAECn8YAAMOAAkKlhQZJAAmAgAOAAkKlhQZJAAmAgACAAEKVhnljQBAAAABNQAFFAgIGgAYAL8YAA==.Nautico:BAAANQADCgUJBQAAAA==.',
Ne='Necrokat:BAAANQAECgQIBwAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Ner:BAAANQAECgQIBAAAAA==.Nezha:BAAANQAECggICQABNQAFFAUIDQAiAC0gAA==.',
Ni='Nicksmonk:BAAANQADCgcIBwAAAA==.Nightmist:BAABNQAECn8mAAInAAoKnQkRLgCAAQAnAAoKnQkRLgCAAQAAAA==.Nihility:BAACNQAFFH8NAAMiAAQKLSCGHwC2AAAiAAMK3yGGHwC2AAAUAAEKyhytDQBTAAA1AAQKfyYAAyIACQrRJeIRAOMCACIACAr4JeIRAOMCABQAAgq6IH1HAKoAAAAA.Ninobrown:BAAANQAECgEIAQAAAA==.Nirgand:BAAANQAECgEIAQABNQAECgoKKAAgAKkQAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Nokoan:BAAANQAECgIIAwAAAA==.Noodlestang:BAABNQAECn8XAAMIAAcKrBA0BQA4AQAPAAYKbRKyEQFvAQAIAAYKAA80BQA4AQAAAA==.Nool:BAAANQAECgMIBAAAAA==.Norest:BAAANQADCggICAAAAA==.Norgand:BAABNQAECn8oAAMgAAoKqRASBgBTAgAgAAoKchASBgBTAgAiAAIKbwxDJgFzAAAAAA==.Noriboness:BAAANQAECgQIBgABNQAECgUICQARAAAAAA==.Nosleep:BAACNQAFFH8MAAIQAAQK+gUTBQCUAAAQAAQK+gUTBQCUAAA1AAQKf0kAAhAACgr8F68NAOIBABAACgr8F68NAOIBAAAA.Notdumb:BAAANQAECgEIAQAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgYIDgAAAA==.Nyduss:BAABNQAECn8fAAIWAAkKJiL9YQB0AgAWAAkKJiL9YQB0AgAAAA==.Nyght:BAAANQADCgUICAAAAA==.Nymphs:BAAANQADCgEIAQABNQAECggIFgANAHgIAA==.Nyraxys:BAABNQAECn8hAAIcAAkKSQvYJACaAQAcAAkKSQvYJACaAQAAAA==.Nyxira:BAAANQAECggICwAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
['Nù']='Nùtter:BAAANQADCgMIAwAAAA==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDwAAAA==.',
Oc='Ocopoko:BAAANQAECggICQAAAA==.',
Od='Oddzmage:BAAANQAECgYICgAAAA==.',
On='Onibushi:BAABNQAECn8kAAIKAAkKghnXZABgAgAKAAkKghnXZABgAgAAAA==.',
Oo='Oof:BAAANQAECgMJAwAAAA==.Oohfookayu:BAABNQAECn8YAAIhAAkKKg3OJABcAQAhAAkKKg3OJABcAQABNQAECgoKQgAHAJchAA==.Oosceola:BAAANQADCgQIBQAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAABNQAECn8kAAIPAAoKcRs8VwDSAgAPAAoKcRs8VwDSAgAAAA==.',
Or='Orastal:BAABNQAECn8wAAMVAAoKnRIACwDxAQAVAAoKnRIACwDxAQAPAAUK5APmiwGuAAABNQAFFAQICAAfADQHAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oruun:BAABNQAECn9FAQIGAAkKGSa+BABdAwAGAAkKGSa+BABdAwAAAA==.',
Os='Osvoldo:BAAANQAECgYICAAAAA==.',
Pa='Paid:BAAANQADCgQIBAAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgQICwAAAA==.Pameliana:BAAANQAECgUICgABNQABCgYIBwARAAAAAA==.Pandadander:BAAANQAECgYIBgABNQAECgUIDAARAAAAAA==.Pandalo:BAAANQAECgIIAgAAAA==.Pandalock:BAABNQAECn8UAAILAAkKjQvjLwAcAQALAAkKjQvjLwAcAQAAAA==.Parasiite:BAABNQAECn8lAAITAAoKQRhBKwDNAQATAAoKQRhBKwDNAQAAAA==.Parasíte:BAAANQABCggICAABNQAECgoKJQATAEEYAA==.',
Pe='Peepocute:BAABNQAECn83AAMOAAoKGRx9EwAqAgAOAAoKGRx9EwAqAgACAAYKrwrTUgBIAQAAAA==.Peghane:BAAANQADCgQIBwAAAA==.Pelarn:BAAANQADCgUIBQAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQAECgcICwAAAA==.Physiowar:BAABNQAECn8gAAIKAAkKgRYChgANAgAKAAkKgRYChgANAgAAAA==.',
Pi='Pickledeath:BAAANQAECgQIBgAAAA==.Pilik:BAAANQABCgYIBgAAAA==.Pirozhki:BAAANQADCgcIDQAAAA==.Pizzapuff:BAAANQAECgUIBwAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECn9PAAMcAAoK1CRnAgCZAwAcAAoK1CRnAgCZAwAfAAYKMR3LDQBuAQAAAA==.Popavkrovi:BAAANQAFFAQIBAAAAA==.Popster:BAAANQADCgYIDgAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prada:BAAANQADCgIIAgAAAA==.Prell:BAAANQAECgQICAAAAA==.Preservation:BAAANQAECgcIEgABNQAFFAUIDQAiAC0gAA==.Primrosé:BAAANQADCgUIBQABNQAECgkJIgAHACQeAA==.Prodipriest:BAABNQAFFH8FAAITAAMKcgnjEAC6AAATAAMKcgnjEAC6AAAAAA==.',
Ps='Psÿko:BAAANQAECgUIBQAAAA==.',
Pu='Puffdragon:BAAANQADCgIIAgAAAA==.Pugi:BAAANQADCgEIAQAAAA==.Punkpally:BAAANQAECgUIDQAAAA==.Pushstickk:BAAANQABCgMIAwABNQAECgEIAgARAAAAAA==.Putridstrike:BAAANQAECggICQABNQAECgkJLwAQAPQkAA==.',
Qt='Qtiy:BAAANQAECgUIBQABNQAECgkJMAAKAMcgAA==.Qtyy:BAABNQAECn8wAAIKAAkKxyAwLwCCAgAKAAkKxyAwLwCCAgAAAA==.',
Qu='Quantaboom:BAAANQADCgYIBgAAAA==.',
Ra='Raawwrr:BAAANQADCggIFAAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Raegyr:BAAANQADCggIDQAAAA==.Ragehound:BAAANQADCgYIBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ralphpalaa:BAAANQADCgEIAQAAAA==.Ramped:BAAANQAECgQICQAAAA==.Ranzor:BAABNQAECn8XAAIQAAoKMRezEAAdAgAQAAoKMRezEAAdAgAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgIIAgAAAA==.Raveyn:BAAANQAECgcIEQAAAA==.Ravn:BAAANQABCgIIAgAAAA==.Razzaa:BAAANQADCgcICAAAAA==.',
Re='Redjak:BAAANQADCggIEAAAAA==.Regino:BAABNQAECn8hAAMJAAcKKw30RQDYAAAWAAYKFAqJBQHhAAAJAAUKRQ/0RQDYAAAAAA==.Reitiado:BAAANQAECgEIAQAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECgkJGwAYAFEQAA==.Rekita:BAABNQAECn8bAAIYAAkKURD6hwD7AQAYAAkKURD6hwD7AQAAAA==.Remedi:BAAANQAECgYIEwAAAA==.Resyoself:BAABNQAECn8YAAISAAYKxwsxmgANAQASAAYKxwsxmgANAQAAAA==.Retispagheti:BAAANQADCggJCAAAAA==.Retnuh:BAABNQAECn86AAIYAAoK8RPvawDqAQAYAAoK8RPvawDqAQAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rheiner:BAAANQADCggICAAAAA==.Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQAECgIIAgAAAA==.',
Ri='Rickoutlaw:BAAANQADCgcIBwAAAA==.Rimmjab:BAABNQAECn8VAAIGAAoKkg18TQChAQAGAAoKkg18TQChAQAAAA==.Rivén:BAAANQAECgYIDgABNQAECgkJIgAHACQeAA==.',
Rn='Rn:BAABNQAECn8WAAIiAAoKGxgWQACSAgAiAAoKGxgWQACSAgAAAA==.',
Ro='Rockypalboa:BAAANQADCgcIBwAAAA==.Roderika:BAAANQAECgQIBAABNQAFFAQIDwADAA4lAA==.Roids:BAAANQADCggIEAAAAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAABNQAECn8fAAIDAAkK9RdsOAAmAgADAAkK9RdsOAAmAgAAAA==.Romanflak:BAAANQAECgIIAwAAAA==.Roostr:BAABNQAECn8xAAIUAAkKEBbTCwA7AgAUAAkKEBbTCwA7AgAAAA==.Rord:BAABNQAECn83AAMWAAoKYyAkXwB7AgAWAAoKYyAkXwB7AgAeAAEKvxS8GwE8AAAAAA==.Rosalei:BAAANQAECggICgAAAA==.Royjacked:BAAANQAECgMIBAAAAA==.',
Ru='Rubberr:BAAANQAECgUICQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAABNQAECn8UAAIYAAkKiAljmgCAAQAYAAkKiAljmgCAAQAAAA==.Runicstrike:BAABNQAECn9UAAQDAAoKsiW7AgBaAwADAAkKdyW7AgBaAwAEAAkKSSOkDABVAwAFAAkKLhk6PgCkAQABNQAECgkJLwAQAPQkAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sackakt:BAAANQADCggIDQAAAA==.Sadeye:BAAANQAECggIDAAAAA==.Sadie:BAABNQAECn8YAAISAAgKJBINiQB7AQASAAgKJBINiQB7AQABNQAECgoKOgAHABslAA==.Sagalia:BAAANQADCgIIAgABNQAECggICAARAAAAAA==.Sahra:BAABNQAECn86AAIHAAoKGyWZAwCwAwAHAAoKGyWZAwCwAwAAAA==.Sanazale:BAABNQAECn8dAAMcAAgKIB7+DQDHAgAcAAgKIB7+DQDHAgAfAAcK2h0aCAAIAgABNQAECgkJIAAcAH8dAA==.Sanctustrike:BAABNQAECn8tAAQWAAoKcyPBXwB6AgAWAAoKrCHBXwB6AgAJAAcKjSDsIwDCAQAeAAMKkB0jzQDhAAABNQAECgkJLwAQAPQkAA==.Sandalin:BAAANQADCgEIAQAAAA==.Saraphina:BAABNQAECn8gAAIPAAkKZAo4kACGAQAPAAkKZAo4kACGAQAAAA==.Saturosix:BAAANQADCggIEgABNQAECgYIBgARAAAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.Sayge:BAAANQABCgMIBAAAAA==.',
Se='Sellandre:BAABNQAECn8fAAMVAAoK1BUMEQB+AQAPAAkKLBJCxwD2AQAVAAcKFhQMEQB+AQAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECgoKKAAgAKkQAA==.Seronja:BAAANQAECgQIBwAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shammywoww:BAAANQADCgIIAgAAAA==.Shazzai:BAABNQAECn8gAAIYAAkKqBm0lQDdAQAYAAkKqBm0lQDdAQAAAA==.Sherfight:BAABNQAECn9QAAMSAAoKSiWeAgAXBAASAAoKSiWeAgAXBAATAAQKMxopQwAbAQAAAA==.Shielddaddy:BAAANQAECgcIDwAAAA==.Shieldsftl:BAABNQAECn8fAAIEAAgKcAxpRQDzAAAEAAgKcAxpRQDzAAABNQAECgkJFAALAI0LAA==.Shiftycent:BAAANQAECggIBQAAAA==.Shnyaga:BAACNQAFFH8GAAISAAQKOA1wGwAXAQASAAQKOA1wGwAXAQA1AAQKf20CBBIACgp6JskAAOkDABIACgp6JskAAOkDABMABAq0H4M3AGkBACQAAwoeGu4aAJEAAAAA.Shockybalboa:BAABNQAECn8bAAMGAAgKTAckgwAJAQAGAAgKTAckgwAJAQANAAEKAADBNwAwAAAAAA==.Shrider:BAAANQADCgYIEgAAAA==.Shunkd:BAAANQAECgYICwAAAA==.Shøcker:BAAANQADCgEIAQAAAA==.',
Si='Sianda:BAAANQABCgYIBwAAAA==.Silandera:BAAANQAECgEIAgAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQABNQAECggIAwARAAAAAA==.Sinsanityz:BAABNQAECn8VAAMSAAgKmhR+dwC1AQASAAcKNxd+dwC1AQATAAIKhgLacQAJAAAAAA==.Sixxsevenn:BAAANQAECgcICwAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQAECgQIBAAAAA==.',
Sk='Skinwalk:BAABNQAECn8rAAIHAAcKNhrCQwAEAgAHAAcKNhrCQwAEAgAAAA==.Skrai:BAAANQAECgQIBQAAAA==.',
Sl='Slackerftw:BAAANQAECgEIAQAAAA==.Slamhog:BAAANQAECgYIBQABNQAECgoKNwAeAJshAA==.Sleew:BAABNQAECn83AAMiAAoK8BygPgCXAgAiAAkKbxygPgCXAgAUAAIKYRULTwCSAAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.Slixer:BAAANQAECgIIBAAAAA==.',
Sm='Smokintrees:BAAANQAECggICwAAAA==.Smorkchop:BAAANQAECgIIAgAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAABNQAECn8YAAIPAAkK2hGoaADiAQAPAAkK2hGoaADiAQAAAA==.',
So='Soggypringle:BAAANQAECgIIAgAAAA==.Solary:BAAANQADCgIIAgAAAA==.Solnath:BAABNQAECn8yAAICAAoKtyOcBwCAAwACAAoKtyOcBwCAAwAAAA==.Sorcha:BAAANQADCgMIAwAAAA==.Souldaddy:BAABNQAECn8VAAIPAAcKNgNY8QDMAAAPAAcKNgNY8QDMAAAAAA==.',
Sp='Spankinstien:BAAANQAECgcICQAAAA==.Specsdraco:BAACNQAFFH8IAAIjAAUKfQ2RFgDXAAAjAAUKfQ2RFgDXAAA1AAQKfzgAAiMACgq8I1wDAKUDACMACgq8I1wDAKUDAAAA.Spewpuke:BAACNQAFFH8FAAMQAAMKtAlWBwBOAAAKAAMKZwJxLAB6AAAQAAEKHhtWBwBOAAA1AAQKf1kAAxAACgqZI18CADADABAACgqZI18CADADAAoACQrPEOWHAAgCAAAA.Spicytomato:BAABNQAECn9EAAQgAAoK7yFlAQBKAwAgAAoK7yFlAQBKAwAiAAIKdyCRAgFSAAAUAAIKxxmBKwBRAAAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAACNQAFFH8IAAISAAIKqA1tLQB6AAASAAIKqA1tLQB6AAA1AAQKfzoAAhIACgptGMsuAIoCABIACgptGMsuAIoCAAAA.Starstorm:BAAANQADCgQIBAABNQAECgoKNwAiAPAcAA==.Stgermain:BAACNQAFFH8GAAISAAQKnRbpGwATAQASAAQKnRbpGwATAQA1AAQKfzMAAxIACgpYHgApAMUCABIACgpYHgApAMUCABMABwq2FMIzAIUBAAAA.Stinkybinks:BAAANQAECgUIBQAAAA==.Stormlotus:BAAANQAECgMICwAAAA==.Stormsorrow:BAABNQAECn8WAAMOAAYKngkzRwAbAQAOAAYKngkzRwAbAQABAAEKAACCOgAXAAAAAA==.Strawberry:BAEANQADCggICQABNQAECgoKLQAXADkQAA==.Strikeanywer:BAAANQAECgQIDQAAAA==.',
Su='Summers:BAAANQAECgUIBgAAAA==.Superstoned:BAAANQAECgEIAQAAAA==.Surudk:BAAANQAECgYICgAAAA==.',
Sy='Sylrana:BAAANQAECgcIEgAAAA==.Sylri:BAAANQAECgQIBAAAAA==.Sylvie:BAAANQAECgYICgABNQAECgoKOgAHABslAA==.',
Ta='Takticel:BAAANQAECgUICwAAAA==.Taktikal:BAAANQADCggICAABNQAECgUICwARAAAAAA==.Taktikell:BAAANQADCgYIBgABNQAECgUICwARAAAAAA==.Taktikil:BAAANQAECgMIAgABNQAECgUICwARAAAAAA==.Talizar:BAAANQADCgEIAQAAAA==.Talrad:BAAANQAECggIEAAAAA==.Tauralyon:BAABNQAECn8bAAIeAAkKnRsiMQBbAgAeAAkKnRsiMQBbAgABNQAECgkJHQAHAPwdAA==.Tazerxface:BAACNQAFFH8JAAIHAAQKhRPyFQAIAQAHAAQKhRPyFQAIAQA1AAQKf1oAAgcACgpXHmoTAB0DAAcACgpXHmoTAB0DAAAA.Tazlmao:BAAANQAECgQIBQAAAA==.',
Te='Tealgos:BAABNQAECn8eAAIfAAYKVAvPIgAyAQAfAAYKVAvPIgAyAQAAAA==.Teenyhands:BAABNQAECn8lAAMVAAkKqAkxEwBaAQAVAAkKqAkxEwBaAQAPAAUKEwHAqQFuAAAAAA==.Teirlily:BAAANQADCgUIBQABNQAECgkJIgAHACQeAA==.Teldrasa:BAAANQAECgQIBQAAAA==.Telerein:BAAANQAECgUICQAAAA==.Tempér:BAAANQADCgUIBQABNQAECgkJIgAHACQeAA==.Teucer:BAAANQAECgQIBgAAAA==.Tewtz:BAAANQADCgQIBAAAAA==.',
Th='Thaiddous:BAABNQAECn82AAIhAAoKNh9ABwATAwAhAAoKNh9ABwATAwAAAA==.Thanx:BAAANQAECgQICAAAAA==.Thealphabear:BAAANQAECgYIEgAAAA==.Thebeefchief:BAACNQAFFH8TAAIhAAYKQR3kAACVAQAhAAYKQR3kAACVAQA1AAQKfygAAiEACgqbIzIFAEsDACEACgqbIzIFAEsDAAAA.Thebigmon:BAABNQAECn8/AAIGAAoKDR4yKwDTAgAGAAoKDR4yKwDTAgAAAA==.Thedabara:BAAANQADCgQIBgAAAA==.Thedon:BAABNQAECn8UAAMYAAYKxgOE7QAmAQAYAAYKxgOE7QAmAQAjAAEKCwNMngAgAAAAAA==.Thelistria:BAAANQADCggICwAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgcICwAAAA==.Thorxx:BAAANQAECgEIAQAAAA==.Thrudtotems:BAAANQAECggIDwAAAA==.Thrudx:BAABNQAECn8jAAMeAAoK9Rb3QwBVAgAeAAoK9Rb3QwBVAgAWAAMKEQzoaAF4AAAAAA==.Thugnastie:BAABNQAECn8jAAIGAAgKBguQeAAjAQAGAAgKBguQeAAjAQAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tickeld:BAAANQADCgIIAgAAAA==.Tika:BAABNQAECn8/AAIVAAoKkxu3BgBZAgAVAAoKkxu3BgBZAgAAAA==.Timeisdruid:BAAANQAECgQIBAAAAA==.Tinytina:BAAANQAECgcIEAAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAABNQAECn8gAAIlAAkKpRUKDQCyAQAlAAkKpRUKDQCyAQAAAA==.Togashi:BAABNQAECn8xAAILAAkKoSD0CwCgAgALAAkKoSD0CwCgAgAAAA==.Toof:BAAANQAECgUIEAAAAA==.Topacio:BAABNQAECn8aAAIhAAgKMQ0BKgA6AQAhAAgKMQ0BKgA6AQAAAA==.Topnacho:BAAANQADCgEIAQABNQAFFAgIGgAYAL8YAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAABNQAECn8lAAMIAAcK0ANMCACfAAAPAAcK0AO0UQEIAQAIAAUK6QFMCACfAAAAAA==.Totesschnook:BAAANQAECggIBgAAAA==.Toymueto:BAAANQAECgUICgAAAA==.',
Tr='Treespirit:BAABNQAECn8gAAInAAoKjB7ODgDnAgAnAAoKjB7ODgDnAgAAAA==.Trenbologne:BAAANQADCgMIAwAAAA==.Trend:BAAANQAECgUIBgAAAA==.Tricep:BAAANQADCggIGAAAAA==.Tripallie:BAAANQAECgEIAQAAAA==.Trishian:BAAANQAECgEIAQAAAA==.Tristis:BAAANQAECgQIBAAAAA==.Troco:BAAANQADCgYIBgAAAA==.Trunkmuffin:BAAANQAECgEIAgAAAA==.Truthless:BAECNQAFFH8KAAIeAAQKrBn7EAAxAQAeAAQKrBn7EAAxAQA1AAQKfysAAh4ACgqgH1APAFEDAB4ACgqgH1APAFEDAAAA.',
Tu='Tuckermax:BAAANQAECgMIBQAAAA==.Tuckser:BAAANQAECgMIAwAAAA==.Tunks:BAAANQAECgYIDwAAAA==.Tusk:BAABNQAECn8dAAIHAAkK/B0bNQCLAgAHAAkK/B0bNQCLAgAAAA==.',
Tw='Twinstar:BAAANQAECgYIBgAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECgoKTwAcANQkAA==.',
Ug='Uglyashell:BAAANQAECgEIAgAAAA==.',
Un='Unit:BAABNQAECn8oAAINAAkKCyPJCwC0AgANAAkKCyPJCwC0AgAAAA==.',
Uv='Uva:BAABNQAECn8eAAIdAAgKKBNsBwCrAQAdAAgKKBNsBwCrAQAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAABNQAECn8sAAIgAAkK8xGbBgBCAgAgAAkK8xGbBgBCAgAAAA==.Valsorin:BAAANQAECgQICQAAAA==.Valtaea:BAACNQAFFH8FAAIPAAQK9AZkLgC5AAAPAAQK9AZkLgC5AAA1AAQKf0YAAg8ACgqyE/RTABYCAA8ACgqyE/RTABYCAAAA.',
Ve='Velanthos:BAAANQAECgEIAQAAAA==.Velour:BAAANQAECgMIBQABNQAECgUIAwARAAAAAA==.Venomshaft:BAAANQAECgQIBQAAAA==.Vershammy:BAAANQAECgEIAQAAAA==.',
Vi='Viciouslock:BAAANQAECgMIBAAAAA==.Vigilus:BAAANQADCggICAAAAA==.Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQJBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgUIDgARAAAAAA==.Voidwaffle:BAAANQADCgcIDQAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Volrog:BAAANQADCgQIBAAAAA==.Voreah:BAAANQAECgQICgABNQAECggIGgATADsOAA==.',
Wa='Waarsêer:BAAANQADCgcIBwAAAA==.Wafflxs:BAACNQAFFH8LAAIbAAYKLyH4AQAiAgAbAAYKLyH4AQAiAgA1AAQKfzMAAhsACgpmJHgDAHoDABsACgpmJHgDAHoDAAAA.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAABNQAECn8jAAIWAAoKyBiedwA9AgAWAAoKyBiedwA9AgAAAA==.Warglave:BAABNQAECn8aAAICAAoKSQ3ANwBoAQACAAoKSQ3ANwBoAQAAAA==.Warmo:BAAANQAECgUIDQAAAA==.Warunk:BAABNQAECn8uAAIjAAkKXiSQAQBfAwAjAAkKXiSQAQBfAwAAAA==.',
Wc='Wcldragon:BAAANQADCgUIBgAAAA==.',
We='Weakdog:BAAANQAECgMIAwAAAA==.Weiwu:BAACNQAFFH8iAAILAAYKuxMWBwAiAQALAAYKuxMWBwAiAQA1AAQKfz8AAgsACgorIDMPAPACAAsACgorIDMPAPACAAAA.Wellfookthat:BAABNQAECn9CAAIHAAoKlyHfDQBSAwAHAAoKlyHfDQBSAwAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECgoKQgAHAJchAA==.',
Wh='Whiteshadows:BAABNQAECn8mAAIWAAkK4Rb1dgA/AgAWAAkK4Rb1dgA/AgAAAA==.Whyvala:BAAANQAECgYIEQABNQADCggILgARAAAAAA==.Whyvara:BAAANQADCggILgAAAA==.',
Wi='Wiisp:BAABNQAECn9AAAIoAAoKtx/uBADRAgAoAAoKtx/uBADRAgAAAA==.',
Wo='Wolneyd:BAAANQAECgYIBQABNQAFFAIICQAWABwkAA==.Wolnney:BAACNQAFFH8JAAIWAAIKHCTiGQDEAAAWAAIKHCTiGQDEAAA1AAQKf2UAAhYACgpmJnEDAOEDABYACgpmJnEDAOEDAAAA.Wowimhealing:BAAANQADCgcIEAAAAA==.',
Wr='Wrath:BAAANQADCgQIBAAAAA==.',
Wu='Wubnah:BAAANQADCgIIAwAAAA==.',
['Wâ']='Wâarseer:BAAANQAECgQIBQAAAA==.',
['Wí']='Wínk:BAAANQADCgYIBgABNQAECgkJIgAHACQeAA==.',
Xa='Xairo:BAAANQAECgUICwAAAA==.Xalatoes:BAACNQAFFH8eAAIHAAgKexq/BQAPAgAHAAgKexq/BQAPAgA1AAQKfzEAAgcACgquHzQeAPMCAAcACgquHzQeAPMCAAAA.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.',
Xi='Xionglieren:BAAANQADCgQIBAABNQAECgUICAARAAAAAA==.Xiren:BAAANQABCgQIBwAAAA==.',
Xr='Xraiz:BAABNQAECn8mAAIhAAoKuA8mIQB6AQAhAAoKuA8mIQB6AQAAAA==.',
Xy='Xyne:BAAANQADCggIEQAAAA==.',
Ya='Yahaloser:BAAANQADCgMIAwAAAA==.Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAACNQAFFH8SAAIbAAUKaR4nAwDWAQAbAAUKaR4nAwDWAQA1AAQKf04AAhsACgp/JJACAJQDABsACgp/JJACAJQDAAAA.Yourboyblue:BAAANQADCgYIHAAAAA==.Yourmaster:BAABNQAECn8lAAMnAAgKQhSjIgDiAQAnAAgKQhSjIgDiAQAmAAUK0gCfsAA1AAAAAA==.',
Yu='Yunna:BAAANQADCggICgAAAA==.',
Yv='Yverrius:BAAANQADCgMICAAAAA==.',
Za='Zanydruid:BAAANQADCgQICQAAAA==.Zanza:BAABNQAECn8dAAIKAAoKYRZtSgAgAgAKAAoKYRZtSgAgAgAAAA==.Zapupa:BAABNQAECn8YAAMSAAkK2SQfBwDBAwASAAkK2SQfBwDBAwATAAEKugV8jgAcAAAAAA==.Zariana:BAAANQAECgIICAAAAA==.Zarione:BAAANQAECgMIBgAAAA==.',
Ze='Zemus:BAAANQADCggIEQAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.Zepbound:BAAANQABCggIFwAAAA==.Zethrak:BAAANQAECgEIAQAAAA==.',
Zh='Zhamazu:BAAANQADCgUIBwAAAA==.Zharost:BAAANQADCggIDgAAAA==.Zhayden:BAABNQAECn8WAAIXAAcKOhf0GwD2AQAXAAcKOhf0GwD2AQAAAA==.Zhy:BAAANQAECgMIAwAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.Zidenko:BAAANQAECgQIBgAAAA==.',
Zo='Zodin:BAAANQAECgIIBAABNQAECggIDAARAAAAAA==.Zombiez:BAABNQAECn8kAAIEAAkKGAkMMgBeAQAEAAkKGAkMMgBeAQAAAA==.Zoov:BAAANQAECggIDAAAAA==.Zoryn:BAAANQAECgQIBgABNQADCggICAARAAAAAA==.',
Zu='Zumalee:BAAANQAECggICAAAAA==.',
Zw='Zwerlin:BAAANQAECgEIAgAAAA==.',
['Âb']='Âbaddön:BAAANQADCgYICwAAAA==.',
['Él']='Élowen:BAAANQAECgIIAwAAAA==.',
['ßi']='ßirdmân:BAABNQAECn8zAAIWAAoK5B4sTACwAgAWAAoK5B4sTACwAgAAAA==.',
['ßo']='ßoß:BAAANQABCggICwAAAA==.',
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
