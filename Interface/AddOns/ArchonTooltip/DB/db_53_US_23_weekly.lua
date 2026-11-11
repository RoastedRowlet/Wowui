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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Mage-Fire','Paladin-Protection','Warrior-Arms','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement','DemonHunter-Devourer','Mage-Arcane','Warrior-Protection','Unknown-Unknown','Priest-Holy','Warlock-Destruction','Mage-Frost','Paladin-Retribution','Priest-Shadow','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Monk-Mistweaver','Evoker-Preservation','Paladin-Holy','Evoker-Devastation','Warlock-Affliction','Druid-Guardian','Warlock-Demonology','Hunter-Marksmanship','Priest-Discipline','Hunter-Survival','Warrior-Fury','Druid-Balance','Druid-Restoration','Druid-Feral',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaradh:BAABNQAECn8lAAMBAAoKbgi+FwA0AQABAAoKbgi+FwA0AQACAAEKqQOpnwAfAAAAAA==.Aaradk:BAABNQAECn8mAAMDAAoKHw1pWACRAQADAAoKHw1pWACRAQAEAAEKRQOx+AAfAAABNQAECgoKJQABAG4IAA==.Aarahunt:BAAANQAECgYICgABNQAECgoKJQABAG4IAA==.',
Ab='Abaddondk:BAABNQAECn8wAAIFAAkKXBQUMADUAQAFAAkKXBQUMADUAQAAAA==.Abilify:BAAANQABCgcIJAAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Aces:BAABNQAECn8bAAMGAAkK4QogdwAQAQAGAAkK4QogdwAQAQAHAAgKuAYntgABAQAAAA==.Acez:BAAANQAECggIEAABNQAECgkJGwAGAOEKAA==.Acidwaste:BAAANQADCggIHAAAAA==.',
Ad='Addilynn:BAABNQAECn8XAAICAAUKpAEBggBvAAACAAUKpAEBggBvAAAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAABNQAECn8+AAIIAAoKmhW3AQCBAgAIAAoKmhW3AQCBAgAAAA==.',
Ae='Aelania:BAABNQAECn8bAAIJAAgKUBE0JQAwAQAJAAgKUBE0JQAwAQAAAA==.Aelunara:BAABNQAECn8lAAMEAAkKJRm/VAC/AQAEAAkKJRm/VAC/AQADAAEKAABzzgAvAAAAAA==.Aemoz:BAAANQAECgQJBAAAAA==.Aerthalis:BAAANQADCgIIAgAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgYIDQAAAA==.',
Ai='Ailric:BAAANQAECgYIDAAAAA==.Ainke:BAAANQADCgYIDgAAAA==.',
Al='Alarakian:BAABNQAECn8iAAIKAAoKlhVWPgA6AgAKAAoKlhVWPgA6AgAAAA==.Alassae:BAAANQAECgYIBgAAAA==.Alexei:BAABNQAECn8yAAMLAAgK2RfXHQCcAQALAAgK2RfXHQCcAQAMAAcK1A1THQATAQAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAABNQAECn8gAAQGAAoKoA08cgDKAQAGAAkK5ws8cgDKAQAHAAUKehD7qwAZAQANAAIK3QP6MQBWAAAAAA==.Alkhan:BAABNQAECn8rAAMCAAkK0QfCQgARAQACAAgKYQjCQgARAQAOAAEKbgTZVwAoAAABNQAFFAQIBQAPAPQGAA==.Allymage:BAAANQADCgMIAwAAAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altheaz:BAAANQAECgIIAgAAAA==.Altoids:BAAANQAECgUIDAAAAA==.Altos:BAACNQAFFH8OAAMQAAQK/gS4BACPAAAQAAQK/gS4BACPAAAKAAEKAABZOwAAAAA1AAQKf0kAAhAACgoVFnQOALgBABAACgoVFnQOALgBAAAA.Altóids:BAAANQAECgQIBAABNQAECgUIDAARAAAAAA==.Alwayshazy:BAAANQADCgUIBQAAAA==.Alyssachik:BAAANQAECgcIDgAAAA==.',
Am='Amdabear:BAAANQADCgcIDAAAAA==.',
An='Anartik:BAAANQAECggICwAAAA==.Anavar:BAAANQADCgYIDwAAAA==.Angerclaw:BAAANQAECgcIDAAAAA==.Animeow:BAABNQAECn8mAAISAAkKGSB7EQA9AwASAAkKGSB7EQA9AwAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.Annaalista:BAAANQABCgcIFAAAAA==.Annasun:BAAANQADCgUIBQABNQAECggIIwATANERAA==.',
Ap='Aplpiemonday:BAAANQADCgcIBwAAAA==.Apoth:BAAANQAECgcICAABNQAECggIDgARAAAAAA==.Apothe:BAAANQAECgUIBQABNQAECggIDgARAAAAAA==.Apotheke:BAAANQAECggIDgAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQAECgEIAQAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAABNQAECn8jAAIPAAkK/BXitwAUAgAPAAkK/BXitwAUAgAAAA==.Arcanofrosty:BAABNQAECn8dAAMUAAcKmAXjJACjAAAPAAYK0QHjggG+AAAUAAYKSQbjJACjAAAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.Arwen:BAAANQABCgIIBAAAAA==.',
At='Atalmon:BAABNQAECn85AAIVAAoKihqMRgBHAgAVAAoKihqMRgBHAgAAAA==.',
Au='Aurochi:BAAANQAECgIIAgAAAA==.',
Av='Avastin:BAAANQAECgEIAQAAAA==.',
Aw='Awni:BAABNQAECn8xAAIKAAkKYxY2eAAuAgAKAAkKYxY2eAAuAgAAAA==.',
Ba='Bacon:BAABNQAECn88AAIWAAoK1A4cHQCQAQAWAAoK1A4cHQCQAQAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAABNQAECn8gAAIPAAkK4R+SYQDkAQAPAAkK4R+SYQDkAQAAAA==.Baknow:BAAANQAECgIIAwAAAA==.Bambuu:BAAANQABCggIDAAAAA==.Bangbangji:BAABNQAECn8VAAIKAAgKihA2ZAC+AQAKAAgKihA2ZAC+AQAAAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAABNQAECn8fAAIPAAgKUQz9pgBEAQAPAAgKUQz9pgBEAQAAAA==.Bartholomeow:BAAANQADCgQIBAAAAA==.Basch:BAAANQABCgYIDAAAAA==.Battlebeats:BAAANQADCgUIBQAAAA==.Bazzoo:BAAANQAECggIDQAAAA==.',
Be='Beachbabe:BAAANQADCgcIBwAAAA==.Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAABNQAECn82AAIXAAoKRB2VLgB6AgAXAAoKRB2VLgB6AgAAAA==.Beeloved:BAAANQADCgYIBgAAAA==.Benzos:BAABNQAECn8zAAQYAAoKriR8CwAtAwAYAAkKmiR8CwAtAwAZAAgKQCGiBAC/AgAaAAIK5SXJsQBxAAAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bethezar:BAAANQAECgcICgAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAABNQAECn8/AAIbAAoKyxpBDgCfAgAbAAoKyxpBDgCfAgAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgUIDgAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQAECgUIEQAAAA==.',
Bl='Bluerose:BAABNQAECn8VAAIXAAUKxgf4/gAHAQAXAAUKxgf4/gAHAQAAAA==.Blurry:BAABNQAECn8jAAITAAgK0REZDAA2AgATAAgK0REZDAA2AgAAAA==.',
Bo='Boltsandhoes:BAAANQADCggICAABNQAECgcIEQARAAAAAA==.Boomidk:BAAANQAECgMIAwAAAA==.Bountmage:BAABNQAECn8mAAMUAAgKvRQbEABvAQAUAAgKvRQbEABvAQAPAAEKAACzcwEAAAAAAA==.Bovinnie:BAAANQAECgMIAwAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brainn:BAAANQADCgUIBQAAAA==.Brillectra:BAAANQAECgMIAQAAAA==.Brisketboy:BAAANQADCgQIBAAAAA==.Bro:BAAANQAECgUIDgAAAA==.Brokentuskz:BAAANQAECggJAQABNQAECgkJMAAFAFwUAA==.Bronthos:BAAANQADCggICAAAAA==.Brothertunks:BAAANQADCgMIAwAAAA==.Brêwski:BAAANQAECgIIAgAAAA==.',
Bu='Budago:BAABNQAECn8UAAIWAAgKSQvqJgA2AQAWAAgKSQvqJgA2AQAAAA==.Buffbutton:BAABNQAECn8tAAIPAAoKsA3LXwDoAQAPAAoKsA3LXwDoAQABNQAECgoKTQAKACwcAA==.Buffstallion:BAAANQAECgQIBwAAAA==.Buzzie:BAAANQADCgcIEgAAAA==.',
['Bï']='Bïllï:BAACNQAFFH8FAAIGAAIK7RSIGgCRAAAGAAIK7RSIGgCRAAA1AAQKfy4AAgYACgr2H34ZADADAAYACgr2H34ZADADAAAA.',
Ca='Caerisma:BAAANQAECggILAAAAQ==.Cakevswaffle:BAAANQAECggIAQAAAA==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Celestino:BAAANQAECgUIBQAAAA==.Cellica:BAAANQAECgQICAAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Chainevoker:BAAANQAECgcIDAAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQAECggIEAABNQAECggILAARAAAAAQ==.Chasity:BAAANQABCgEIAQAAAA==.Chiang:BAAANQAECggIDAAAAA==.Chilijayleen:BAAANQAECgYIBgABNQAECgoKLwAXAHYSAA==.Chlena:BAABNQAFFH8FAAIcAAUKLhVSCQBtAQAcAAUKLhVSCQBtAQAAAA==.Chudmax:BAAANQADCgYIDQAAAA==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUJBgAAAA==.',
Cl='Clegen:BAAANQADCggIDQAAAA==.Cloax:BAACNQAFFH8MAAIWAAQKVxXKCADwAAAWAAQKVxXKCADwAAA1AAQKf0gAAhYACgrOIe8FAAsDABYACgrOIe8FAAsDAAAA.Cláp:BAABNQAFFH8HAAIQAAcK6xUxAQDrAQAQAAcK6xUxAQDrAQAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAEANQADCggIDgABNQAECgoKJwAaADkQAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Conquerlock:BAAANQAECgMIAwAAAA==.Coobibrains:BAAANQADCgUIBwAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCggIDQAAAA==.Cory:BAAANQADCgMIAwAAAA==.Cowchipp:BAAANQADCgUIBQAAAA==.',
Cr='Craerman:BAAANQADCgYICwABNQAECggILAARAAAAAQ==.Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Crewbin:BAAANQADCggICAAAAA==.Croobin:BAAANQADCggICAAAAA==.Cryhavok:BAACNQAFFH8MAAMVAAQKABJ/FADWAAAVAAMKABJ/FADWAAAdAAIK0gKqJwA9AAA1AAQKf0MAAxUACgo8HbI4AHQCABUACgo8HbI4AHQCAB0AAgquDsIAAXkAAAAA.',
Cu='Cussack:BAABNQAECn8uAAIKAAoKyiLyHABEAwAKAAoKyiLyHABEAwAAAA==.Cutepandaa:BAAANQADCgQIBAAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECggIFQAKAIoQAA==.Daghar:BAAANQAECgIJAwAAAA==.Dagoatfr:BAAANQADCggIEgAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAABNQAECn8jAAIKAAoKaw3YWwDXAQAKAAoKaw3YWwDXAQABNQAECggIFAAWAEkLAA==.Danui:BAAANQADCgQIBAAAAA==.Danuth:BAAANQADCgUIBQAAAA==.Darkgol:BAABNQAECn8jAAIKAAgKwA2qbgCgAQAKAAgKwA2qbgCgAQABNQAECgoKMAAVAEMSAA==.Darkshammys:BAAANQAECgEIAQAAAA==.Darkshayd:BAAANQADCgIIAgAAAA==.Davioon:BAAANQAECgIIBQAAAA==.Dayrb:BAAANQAFFAEIAQAAAA==.',
Db='Dblade:BAAANQAFFAQIBAAAAA==.',
De='Deadlyheal:BAAANQAECggIDgABNQADCggICAARAAAAAA==.Deadtalini:BAACNQAFFH8KAAMDAAUKxA0dFwCjAAADAAUKjg0dFwCjAAAFAAIKiwk9FwByAAA1AAQKfz8AAwUACgpjH3oYAMYCAAUACgpmGnoYAMYCAAMACgpqGws5ACICAAAA.Deah:BAABNQAECn8nAAIXAAkKSyHYDgASAwAXAAkKSyHYDgASAwAAAA==.Deathstarr:BAAANQADCggICQAAAA==.Deaththroes:BAAANQAECgQIBQAAAA==.Deckerdramon:BAABNQAECn86AAIQAAoKjxp5CQC0AgAQAAoKjxp5CQC0AgAAAA==.Demomachin:BAABNQAECn82AAIBAAoKeRoiBwAKAgABAAoKeRoiBwAKAgAAAA==.Demonnoodle:BAAANQADCggICQABNQAECgcIFwAIAKwQAA==.Demonsfear:BAABNQAECn8tAAIOAAoKThvMGQCLAgAOAAoKThvMGQCLAgAAAA==.Demyze:BAAANQADCggIEAAAAA==.Denorak:BAAANQAECgUICQAAAA==.Densetsu:BAAANQADCgcJBwAAAA==.Destroyera:BAAANQAECgcIBwAAAA==.Deucalyon:BAAANQADCggIJAAAAA==.Devanaa:BAAANQADCgYIBgAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devourme:BAAANQAECgIIAgABNQAFFAcIGgAHAKsZAA==.Devours:BAACNQAFFH8aAAIHAAcKqxk6CwCZAQAHAAcKqxk6CwCZAQA1AAQKfywAAgcACgriHPgvAKICAAcACgriHPgvAKICAAAA.Devuledegg:BAAANQADCgEIAQAAAA==.',
Di='Dirtyhooves:BAAANQADCggIDwABNQAECgMIBAARAAAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAACNQAFFH8ZAAIbAAcKKyatAACOAgAbAAcKKyatAACOAgA1AAQKfzUAAhsACgr0JiIAAAEEABsACgr0JiIAAAEEAAAA.',
Do='Doesdrool:BAAANQADCgEIAQAAAA==.Dohtem:BAAANQADCgYICwABNQAECgkJIwANAM4cAA==.Donmegah:BAAANQAECgUIDgAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Draemon:BAAANQADCgEIAQAAAA==.Dragapult:BAABNQAECn8fAAIeAAoKphkABQBnAgAeAAoKphkABQBnAgABNQAFFAQIDwADAA4lAA==.Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Dragusysmash:BAAANQAECgIIAQAAAA==.Draki:BAAANQADCgYIEAAAAA==.Drazzin:BAAANQADCgEIAQABNQAECgoKKAAfAKkQAA==.Dredtotem:BAAANQAECgUICQAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Durzaxda:BAAANQAECgEIAQAAAA==.Dusky:BAAANQABCgYICgAAAA==.Dutanu:BAAANQAECgUICQABNQAECgkJOQAVACcfAA==.',
['Dö']='Dötcom:BAAANQADCgYIDAAAAA==.',
Ec='Echpochmak:BAABNQAECn8aAAISAAkK3SNcDwBSAwASAAkK3SNcDwBSAwAAAA==.',
Ei='Eibhlean:BAABNQAECn8wAAIJAAkKhRSIHAB2AQAJAAkKhRSIHAB2AQABNQAECgQICQARAAAAAA==.Eireckt:BAAANQADCgcIDAAAAA==.Eirrin:BAAANQAFFAEIAQAAAA==.Eivorr:BAAANQABCgQJAgAAAA==.',
El='Elariin:BAABNQAECn8gAAMHAAgK9xvSawDIAQAHAAcK7BvSawDIAQAGAAQKGgx2rQCZAAAAAA==.Elaril:BAAANQADCggIGwAAAA==.Eleforever:BAACNQAFFH8FAAIGAAIK4BpAIQCoAAAGAAIK4BpAIQCoAAA1AAQKfz4AAgYACgpWIv4VAEUDAAYACgpWIv4VAEUDAAAA.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcIBwAAAA==.Elleredreaux:BAAANQAECggICgAAAA==.',
Em='Emongar:BAAANQAECgQIBQAAAA==.',
En='Endomorphism:BAAANQAECgIIAgABNQAFFAgIGgAgACghAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ev='Eveldumboone:BAAANQAECgIIAgABNQAFFAYIEwAgAEEdAA==.Evlynia:BAAANQADCgMIAgAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAABNQAECn8sAAIhAAoKZw+JgADlAQAhAAoKZw+JgADlAQAAAA==.',
Fa='Fableshoot:BAAANQAECgUIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgARAAAAAA==.Fangtang:BAAANQAECggICAAAAA==.Fantasie:BAAANQAECgEIAQABNQAECgoKRgASADskAA==.Fatherclutch:BAAANQADCgQICAABNQAECggIHAAMANAMAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAACNQAFFH8JAAIXAAQKZw5eFADfAAAXAAQKZw5eFADfAAA1AAQKf0QAAxcACgpeIGQdAL8CABcACgpeIGQdAL8CACIAAwreCCNnAI8AAAAA.',
Fe='Fearfactor:BAAANQADCgQIBAAAAA==.Felpal:BAAANQABCgMIAQABNQAECgYIHgAeAFQLAA==.Felwoof:BAABNQAECn86AAQTAAoKTiHNCgACAQAhAAUKTB7RmgCkAQAfAAcKXCFxCgCMAQATAAMKPB7NCgACAQAAAA==.Felzak:BAAANQADCgYIBgABNQAECgUICwARAAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgcIFwAAAA==.Fistachio:BAAANQADCggIEgAAAA==.',
Fl='Flarllek:BAAANQADCgYIFAAAAA==.Flexxed:BAABNQAECn8jAAIFAAkKhyHgFgDUAgAFAAkKhyHgFgDUAgAAAA==.Floorlock:BAAANQADCgUIBQAAAA==.Florin:BAAANQAECgIIBQAAAA==.',
Fo='Foopz:BAAANQADCgIJAgABNQAECgEIAgARAAAAAA==.Forthehordde:BAAANQABCgcICwAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Freddybones:BAAANQAECgEIAgAAAA==.Friendlytwo:BAAANQADCggIDgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgUICwABNQAECgoKRgASADskAA==.Frostyduggo:BAABNQAECn82AAIUAAoKjwsWDgCVAQAUAAoKjwsWDgCVAQAAAA==.Frostyxz:BAAANQADCgQIBAAAAA==.Fry:BAACNQAFFH8YAAIWAAcKARN3BQDgAQAWAAcKARN3BQDgAQA1AAQKfysAAhYACgp5H5QWAKcCABYACgp5H5QWAKcCAAAA.Fríeren:BAAANQADCgIIAgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgYIEAAAAA==.Fumblemore:BAAANQADCgEIAQAAAA==.Furystrike:BAABNQAECn8vAAMQAAkK9CRkBgAAAwAQAAkK5SJkBgAAAwAKAAkKzh/GQwC+AgAAAA==.Futbuckmcgee:BAAANQADCggICAAAAA==.Fuupa:BAAANQADCgIIAgABNQAECgEIAgARAAAAAA==.',
Ga='Galixie:BAAANQABCgQIBgAAAA==.Ganondrow:BAABNQAECn82AAQWAAoKkCIaCgCwAgAWAAoKkCIaCgCwAgASAAMKqhrmtAD4AAAjAAEKng6XJgA8AAAAAA==.',
Ge='Gehagnute:BAAANQADCgEIAQAAAA==.Gemelo:BAABNQAECn8nAAIkAAoKHhUdBQABAgAkAAoKHhUdBQABAgAAAA==.Geromul:BAAANQAECgYIBwAAAA==.Gerrexs:BAABNQAECn8VAAIKAAgKOhA9swCdAQAKAAgKOhA9swCdAQAAAA==.',
Gi='Gibayy:BAABNQAECn8YAAIPAAcKcx6psgAeAgAPAAcKcx6psgAeAgAAAA==.Gibsonex:BAAANQAECgYIDAAAAA==.Gideone:BAAANQADCgYICgAAAA==.Gildagni:BAAANQAECgMIAwAAAA==.Gilliamm:BAABNQAECn8/AAMaAAoKGBaaWgCBAQAaAAgK4BeaWgCBAQAYAAUKWxJrWgBPAQAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Gn='Gnorman:BAAANQADCgIIAgAAAA==.',
Go='Golath:BAABNQAECn8wAAIVAAoKQxKWgAC3AQAVAAoKQxKWgAC3AQAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAABNQAECn8hAAIXAAkKYgQKwgATAQAXAAkKYgQKwgATAQAAAA==.Gothbutta:BAAANQAECgQICgAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Grandena:BAAANQADCgUICgAAAA==.Graydeon:BAAANQAECggIEQAAAA==.Greatangel:BAAANQADCgUIBAABNQAECggIIwATANERAA==.Gregano:BAAANQAECgUIBAABNQAECgkJHgAKACkMAA==.Gregorian:BAABNQAECn8eAAIKAAkKKQwBqQC2AQAKAAkKKQwBqQC2AQAAAA==.Gremliin:BAACNQAFFH8OAAISAAUKcxQ/EQB3AQASAAUKcxQ/EQB3AQA1AAQKfz0AAhIACgq8HnoWAB8DABIACgq8HnoWAB8DAAAA.Gremliinss:BAAANQAECgcIBwAAAA==.Gretch:BAAANQAECgUIBQAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Gu='Gunnerbe:BAAANQADCgYICQAAAA==.',
Ha='Hadesdecends:BAAANQADCgMIAwAAAA==.Halakal:BAAANQAECgUICwAAAA==.Halparogue:BAAANQADCgIIAgAAAA==.Hammerbell:BAAANQAECggJCAAAAA==.Haviboomer:BAAANQAECgQICAAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.',
He='Healmeharder:BAAANQADCgIIAgAAAA==.Healminth:BAAANQAFFAUIAgAAAA==.Healthcare:BAAANQAECgIIAgAAAA==.Healuminati:BAAANQAECgYIBgAAAA==.Herbatron:BAAANQAECgEIAQAAAA==.Hethar:BAAANQAECgEIAQAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hightide:BAAANQAECggIEgAAAA==.Hilltop:BAAANQABCgEIAQAAAA==.Hippo:BAAANQAECgYIEAAAAA==.',
Ho='Hoja:BAAANQAECggIEgAAAA==.Holdor:BAAANQADCgUIBgAAAA==.Holdors:BAAANQADCggIDAAAAA==.Holier:BAAANQADCgYIBgABNQADCggJCAARAAAAAA==.Holybloodboi:BAAANQAECgEJAQABNQAECgoKKQAHAKUkAA==.Holybuns:BAAANQAECgIIAgAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIBQABNQAECgcIFwAIAKwQAA==.',
Ht='Htilogak:BAAANQAECgMIAwAAAA==.',
Hu='Hunglikabull:BAAANQAECgUIBQAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAABNQAECgYIBwARAAAAAA==.',
Ic='Iceangell:BAAANQAECgYIBgAAAA==.Iceberg:BAAANQADCgYIBgAAAA==.Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQAECgMIAwAAAA==.',
In='Insanegrippy:BAABNQAECn8UAAIDAAkKvBnBGwARAgADAAkKvBnBGwARAgABNQAFFAgIHgAHAHsaAA==.Intaria:BAACNQAFFH8IAAIKAAMKugMVJACRAAAKAAMKugMVJACRAAA1AAQKfy4AAwoACgqVFSl0ADgCAAoACgpgFSl0ADgCACUAAwpDFHoiAKMAAAAA.Invisibulity:BAAANQADCgYICQABNQAECgYIHgAeAFQLAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgMIAgAAAA==.Itsrambo:BAABNQAECn8lAAIVAAoKDxZhgQC1AQAVAAoKDxZhgQC1AQAAAA==.',
Ja='Jackbeef:BAACNQAFFH8HAAIlAAIKLBpAAgCPAAAlAAIKLBpAAgCPAAA1AAQKf0IAAiUACgoFJacAAGcDACUACgoFJacAAGcDAAAA.Jadedhooves:BAABNQAECn8rAAIVAAcKiRCj4wBUAQAVAAcKiRCj4wBUAQAAAA==.Jaggedlilhun:BAABNQAECn8vAAIXAAoKdhJ4aADZAQAXAAoKdhJ4aADZAQAAAA==.Jaggedshammy:BAABNQAECn8cAAIGAAgKXQlnXwBQAQAGAAgKXQlnXwBQAQABNQAECgoKLwAXAHYSAA==.Jagruk:BAAANQADCgIIAgABNQAECgUICwARAAAAAA==.Jak:BAAANQADCgUIBQAAAA==.Janwalutala:BAAANQADCgYIBgAAAA==.Jareyk:BAABNQAECn86AAMdAAoKvRzfQgBZAgAdAAoKvRzfQgBZAgAVAAEKAADYwQEAAAAAAA==.Jarladorin:BAAANQAECgIIAwABNQAECgkJHgAKAKcPAA==.Jarlu:BAAANQAECggICgAAAA==.Jaxodk:BAABNQAECn8mAAMEAAkK+CEdFgAKAwAEAAgKqiIdFgAKAwAFAAkKlR4eIQCEAgAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jecka:BAAANQAECgEIAgAAAA==.Jecynth:BAAANQADCggICgAAAA==.Jedai:BAACNQAFFH8RAAIdAAUK8RMgDABuAQAdAAUK8RMgDABuAQA1AAQKf0kAAh0ACgrIItsJAHgDAB0ACgrIItsJAHgDAAAA.Jellybeann:BAAANQADCgUIEQAAAA==.Jerryfour:BAAANQAECgMIAwAAAA==.Jerrysix:BAABNQAECn8rAAMWAAkK0BOlKQDbAQAWAAgK/hSlKQDbAQAjAAkKOxVVBQCoAQAAAA==.Jerrytwo:BAAANQAECgQIBgAAAA==.',
Ji='Jilseponie:BAAANQABCgIIAgABNQAECgkJFAALAI0LAA==.Jimmypop:BAAANQADCggIFAAAAA==.',
Ju='Judadiah:BAABNQAECn8eAAIKAAkKpw/dsQCgAQAKAAkKpw/dsQCgAQAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgUIBwAAAA==.',
['Jà']='Jàxx:BAABNQAECn8eAAIHAAkKjxyNOQAcAgAHAAkKjxyNOQAcAgAAAA==.',
['Jä']='Jänice:BAAANQAECggIAQAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECgoKLwAXAHYSAA==.',
Ka='Kaanha:BAAANQADCgEIAQAAAA==.Kaego:BAAANQAECgEIAQABNQAECgoKOQAmAMEWAA==.Kalinzern:BAAANQADCgEIAQAAAA==.Kalona:BAAANQADCgUICQAAAA==.Kalrock:BAABNQAECn8YAAMhAAkKeBfsiADQAQAhAAgKjhfsiADQAQATAAEK8hbKcAA+AAAAAA==.Kalrotten:BAAANQADCgcICgABNQAECgkJGAAhAHgXAA==.Kalulu:BAAANQADCggIGQAAAA==.Kalyssi:BAAANQAECgQIBgAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Karkit:BAAANQAECgUICgAAAA==.Katigotbandz:BAABNQAECn8ZAAIVAAkKohd5ewDCAQAVAAkKohd5ewDCAQAAAA==.Katkot:BAABNQAECn8jAAIVAAoK7BaKlQD4AQAVAAoK7BaKlQD4AQAAAA==.Kayro:BAAANQADCgUICAAAAA==.Kazalandera:BAAANQADCgQICAAAAA==.Kazlan:BAAANQAECgQIBwAAAA==.Kazplan:BAAANQAECgUIBQAAAA==.Kazzulee:BAAANQADCgEIAQAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.Kepchuk:BAABNQAECn8fAAIcAAkKdyQoAgCpAwAcAAkKdyQoAgCpAwAAAA==.Keres:BAACNQAFFH8PAAIDAAQKDiUJDQCDAQADAAQKDiUJDQCDAQA1AAQKfy4AAgMACgqcJI0HAIIDAAMACgqcJI0HAIIDAAAA.Keselip:BAAANQAECgYIBwAAAA==.',
Kh='Khagolith:BAABNQAECn85AAImAAoKwRYUJwCwAQAmAAoKwRYUJwCwAQAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.Kirstinn:BAAANQAECgYICQAAAA==.Kizzazz:BAAANQADCgUIBQAAAA==.',
Kk='Kkodabear:BAAANQAECgIIBAAAAA==.',
Kl='Klixeas:BAAANQAECgYIEAAAAA==.',
Kn='Knïghtshädë:BAAANQADCgUIBQAAAA==.',
Ko='Kobiter:BAABNQAECn8qAAQVAAkKRRWJnADpAQAVAAkKHBWJnADpAQAdAAgKjwz2egCoAQAJAAUKuA5KTwCqAAABNQAFFAMIBwAQAOMYAA==.Kobito:BAACNQAFFH8HAAIQAAMK4xjQAgDdAAAQAAMK4xjQAgDdAAA1AAQKf0kAAxAACgpMI/MCAHoDABAACgpMI/MCAHoDAAoABwp0EtmTAEQBAAAA.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECn9MAAMXAAoKMiXLBAC/AwAXAAoKMiXLBAC/AwAiAAMKMxBbSQBsAAAAAA==.Koupe:BAABNQAECn8xAAMnAAoKKRtkDgDIAgAnAAoKKRtkDgDIAgAmAAUKDhCmbwAMAQABNQAECgoKTAAXADIlAA==.',
Kr='Krang:BAAANQAECggICAAAAA==.Kranx:BAAANQAECgMIAwABNQAECgMIBQARAAAAAA==.Krayzebeef:BAAANQAECgQIDwABNQAECgUIDgARAAAAAA==.Kriss:BAABNQAECn8eAAIXAAcK5wiSygACAQAXAAcK5wiSygACAQAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgoKTAAXADIlAA==.Kurirne:BAAANQADCgQIBQAAAA==.Kurkanak:BAAANQAECgIIAgAAAA==.',
Ky='Kyewanda:BAAANQAECggIEwAAAA==.Kyusakuu:BAAANQAECgYIDAABNQAFFAUIDQAhAC0gAA==.',
La='Laanu:BAAANQAECgIIAgABNQAECgoKRgAaABEdAA==.Laci:BAAANQADCggIDgAAAA==.Lagurtalokbr:BAAANQADCgIIAgAAAA==.Lahey:BAACNQAFFH8PAAIKAAUKKhXLFQDpAAAKAAUKKhXLFQDpAAA1AAQKf0gAAgoACgpAHZk7AEQCAAoACgpAHZk7AEQCAAAA.Lakes:BAAANQAECgYIDgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lasucia:BAAANQADCggICAAAAA==.Lathara:BAAANQAECgUIDgAAAA==.Laughzfalcon:BAAANQAECgYIBwAAAA==.Lavs:BAABNQAECn8kAAIoAAgK1R/fCQAmAgAoAAgK1R/fCQAmAgAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.Layona:BAAANQADCggICAAAAA==.',
Ld='Ldykillshot:BAAANQAECgMIBAAAAA==.',
Le='Legatto:BAAANQADCgIIAgAAAA==.Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAABNQAECn8UAAIVAAgKyxKQtQCzAQAVAAgKyxKQtQCzAQAAAA==.Lexiah:BAABNQAECn8iAAMSAAcKaggRmgD1AAASAAcKaggRmgD1AAAWAAEKAAA4kwAVAAAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lilliana:BAAANQAECgEIAQABNQAECgkJIAAPAGQKAA==.Linneasage:BAAANQADCgQIBAAAAA==.Lionofjudah:BAAANQABCgYIDQAAAA==.Lizardbrain:BAAANQAECgMIBwAAAQ==.',
Lo='Loamathor:BAAANQAECgcIEQAAAA==.Lockkdown:BAAANQADCgYIBgAAAA==.Loesh:BAAANQADCgIJAgAAAA==.Lohharhuuk:BAAANQADCggICAAAAA==.Lolyoumad:BAAANQAECgcIDwABNQAECgkJMAASAHYcAA==.Lorcat:BAAANQAECgEIAQAAAA==.Lorilyn:BAABNQAECn8uAAISAAgK1R0wNwBMAgASAAgK1R0wNwBMAgAAAA==.Lorthag:BAABNQAECn8/AAIjAAkKoxPSAwATAgAjAAkKoxPSAwATAgAAAA==.Lovebuz:BAAANQAECgQIBAAAAA==.Loveles:BAAANQADCggICAAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCggIDwAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Luki:BAAANQABCggIDwAAAA==.Lulbah:BAABNQAECn8UAAIgAAcK5BtuFQARAgAgAAcK5BtuFQARAgAAAA==.Lunachick:BAAANQAECgEIAQAAAA==.Lunareclips:BAAANQADCgMIBAAAAA==.Lunarus:BAABNQAECn8pAAIfAAgKFQ4RCwC/AQAfAAgKFQ4RCwC/AQAAAA==.Luniare:BAAANQAECgUIBAAAAA==.',
['Lì']='Lìfe:BAABNQAECn8jAAIKAAgKZxfidgAxAgAKAAgKZxfidgAxAgAAAA==.',
['Ló']='Lónnie:BAAANQAECgMIAwAAAA==.Lónnìe:BAAANQAECgcIEAAAAA==.Lónníe:BAAANQAECgQICQAAAA==.',
Ma='Macloving:BAAANQAECgYIEAAAAA==.Maelona:BAAANQAECggIDAAAAA==.Maen:BAAANQAECgIIBAAAAA==.Magrumok:BAABNQAECn8jAAIEAAoKhBvxGgD7AQAEAAoKhBvxGgD7AQAAAA==.Magthars:BAAANQAECgMIBQAAAA==.Magtide:BAACNQAFFH8LAAIiAAQKFBmXEAAyAQAiAAQKFBmXEAAyAQA1AAQKfxQAAiIACAqMIFsYAJUCACIACAqMIFsYAJUCAAAA.Malväryx:BAABNQAECn8tAAIOAAkKPA0aKABCAQAOAAkKPA0aKABCAQAAAA==.Manbearpig:BAACNQAFFH8JAAIXAAYKzRN6DACKAQAXAAYKzRN6DACKAQA1AAQKfzoAAhcACgrDIrMVAEUDABcACgrDIrMVAEUDAAAA.Manman:BAAANQAECgMIBAAAAA==.Marqose:BAAANQADCgcIBwABNQAECgUICwARAAAAAA==.Marshes:BAAANQADCgIIAgABNQAECgYIDgARAAAAAA==.Masshooter:BAAANQAECgEIAQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mcquade:BAAANQABCgIIAgABNQABCgcIBwARAAAAAA==.Mctigly:BAAANQAECgYIEAAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAABNQAECn84AAIPAAoKxBs3dgCRAgAPAAoKxBs3dgCRAgAAAA==.Mellindre:BAAANQAECgQICgAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAABNQAECn8aAAIJAAgKsQygMQBTAQAJAAgKsQygMQBTAQAAAA==.Merlinsmom:BAAANQADCggICAAAAA==.Mesa:BAACNQAFFH8GAAIcAAQKQhbOCgA6AQAcAAQKQhbOCgA6AQA1AAQKf1kCAxwACgrHJgwAABAEABwACgrHJgwAABAEAB4AAQoaEv44AEYAAAAA.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Micaelia:BAAANQAECgQIBAAAAA==.Miclovin:BAABNQAECn8lAAMaAAkKGRipDQCbAgAaAAkKDxipDQCbAgAYAAIKBwVGlwBXAAAAAA==.Microplastic:BAABNQAECn9NAAMKAAoKLBx1OABQAgAKAAoKLBx1OABQAgAQAAYK5RMnJADDAAAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikelmyers:BAAANQAECgUIBwAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAABNQAECn9KAAIEAAoKjRvyEQBcAgAEAAoKjRvyEQBcAgAAAA==.Minigunn:BAAANQADCggIEAAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQAECgMIAwAAAA==.Misosmol:BAAANQAECgUICwAAAA==.Misowise:BAAANQAECgcIBwAAAA==.Missogyny:BAABNQAECn8kAAIPAAkK0SD8RAD5AgAPAAkK0SD8RAD5AgAAAA==.Miste:BAAANQADCgMIAwAAAA==.Mistie:BAAANQAECgIIAQAAAA==.Mithunzi:BAAANQAECgYIDQAAAA==.',
Mo='Moadeab:BAAANQAECggICgAAAA==.Mogando:BAAANQAECgEIAgABNQAECgoKKAAfAKkQAA==.Mogrodeath:BAAANQAECgUICAABNQAECgoKPwAhAFwgAA==.Mogrodrag:BAAANQADCggICAABNQAECgoKPwAhAFwgAA==.Mogrodruid:BAAANQADCgYIBgABNQAECgoKPwAhAFwgAA==.Mogrogarg:BAABNQAECn8/AAQhAAoKXCAcKwDYAgAhAAoK5h8cKwDYAgATAAQKah9vDQDeAAAfAAEKvB+XJABcAAAAAA==.Mogrosham:BAAANQAECgcIEgABNQAECgoKPwAhAFwgAA==.Mogrougarg:BAAANQAECgIIAgABNQAECgoKPwAhAFwgAA==.Mojojojò:BAABNQAECn8ZAAMPAAcKBAqtxAAMAQAPAAcKBAqtxAAMAQAUAAMKrQMBMwBuAAAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgoKQgAeACcdAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAFFAIIAgAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQAECgUIBQAAAA==.Moribelar:BAAANQAECgUICAAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAABNQAECn8nAAIXAAoKQB5+GgDNAgAXAAoKQB5+GgDNAgAAAA==.Morventhas:BAAANQADCggICQAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAABNQAECn8fAAIXAAoK9w7oaQDVAQAXAAoK9w7oaQDVAQAAAA==.Mousyz:BAAANQAECgcICAAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Mudflapper:BAAANQAECgQIBAAAAA==.Munric:BAABNQAECn88AAIVAAoKMggftgBOAQAVAAoKMggftgBOAQAAAA==.Munusku:BAABNQAECn8bAAIHAAgKuRBvagBeAQAHAAgKuRBvagBeAQAAAA==.Murphh:BAAANQAECggIAwAAAA==.',
My='Myboycleetus:BAAANQAECgUIDAAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQICAAAAA==.',
['Mï']='Mïkasa:BAABNQAECn8cAAIXAAoKAgv8fQCjAQAXAAoKAgv8fQCjAQAAAA==.',
Na='Nachobussy:BAACNQAFFH8aAAMXAAgKvxgBBwDfAQAXAAcKnhoBBwDfAQAiAAYKUA95DgBWAQA1AAQKfywAAxcACgqtJdoPAAsDABcACAohJtoPAAsDACIABwoXG5kcAIEBAAAA.Nachothings:BAABNQAECn8YAAMOAAkKlhQZJAAmAgAOAAkKlhQZJAAmAgACAAEKVhnljQBAAAABNQAFFAgIGgAXAL8YAA==.Nautico:BAAANQADCgUJBQAAAA==.',
Ne='Necrokat:BAAANQAECgQIBwAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Ner:BAAANQAECgQIBAAAAA==.Nezha:BAAANQAECggICQABNQAFFAUIDQAhAC0gAA==.',
Ni='Nicksmonk:BAAANQADCgcIBwAAAA==.Nightmist:BAABNQAECn8ZAAInAAgK0QmJNQAvAQAnAAgK0QmJNQAvAQAAAA==.Nihility:BAACNQAFFH8NAAMhAAQKLSDnGwC5AAAhAAMK3yHnGwC5AAATAAEKyhxbDABUAAA1AAQKfyYAAyEACQrRJZAPAOgCACEACAr4JZAPAOgCABMAAgq6IH1HAKoAAAAA.Ninobrown:BAAANQAECgEIAQAAAA==.Nirgand:BAAANQAECgEIAQABNQAECgoKKAAfAKkQAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Nokoan:BAAANQAECgIIAwAAAA==.Noodlestang:BAABNQAECn8XAAMIAAcKrBA0BQA4AQAPAAYKbRKyEQFvAQAIAAYKAA80BQA4AQAAAA==.Nool:BAAANQAECgMIBAAAAA==.Norest:BAAANQADCggICAAAAA==.Norgand:BAABNQAECn8oAAMfAAoKqRASBgBTAgAfAAoKchASBgBTAgAhAAIKbwxDJgFzAAAAAA==.Noriboness:BAAANQAECgQIBgABNQAECgUICQARAAAAAA==.Nosleep:BAACNQAFFH8MAAIQAAQK+gWKBACYAAAQAAQK+gWKBACYAAA1AAQKf0UAAhAACgr8F1IMAOUBABAACgr8F1IMAOUBAAAA.Notdumb:BAAANQAECgEIAQAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgYIDAAAAA==.Nyduss:BAABNQAECn8dAAIVAAkKIyL9YQB0AgAVAAkKIyL9YQB0AgAAAA==.Nyght:BAAANQADCgUICAAAAA==.Nymphs:BAAANQADCgEIAQABNQAECgkJMAASAHYcAA==.Nyraxys:BAABNQAECn8hAAIcAAkKSQvYJACaAQAcAAkKSQvYJACaAQAAAA==.Nyxira:BAAANQAECggIBwAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
['Nù']='Nùtter:BAAANQADCgMIAwAAAA==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDwAAAA==.',
Oc='Ocopoko:BAAANQAECggICQAAAA==.',
Od='Oddzmage:BAAANQAECgYICgAAAA==.',
On='Onibushi:BAABNQAECn8kAAIKAAkKghnXZABgAgAKAAkKghnXZABgAgAAAA==.',
Oo='Oof:BAAANQAECgMJAwAAAA==.Oohfookayu:BAABNQAECn8YAAIgAAkKKg0kIQBiAQAgAAkKKg0kIQBiAQABNQAECgoKQgAHAJchAA==.Oosceola:BAAANQADCgQIBQAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAABNQAECn8kAAIPAAoKcRs8VwDSAgAPAAoKcRs8VwDSAgAAAA==.',
Or='Orastal:BAABNQAECn8wAAMUAAoKnRKWCQD1AQAUAAoKnRKWCQD1AQAPAAUK5APmiwGuAAABNQAFFAQICAAeADQHAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oruun:BAABNQAECn8hAQIGAAkKGSbwBABWAwAGAAkKGSbwBABWAwAAAA==.',
Os='Osvoldo:BAAANQAECgYIBgAAAA==.',
Pa='Paid:BAAANQADCgQIBAAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgQICwAAAA==.Pameliana:BAAANQAECgUICgABNQABCgYIBwARAAAAAA==.Pandadander:BAAANQAECgYIBgABNQAECgUIDAARAAAAAA==.Pandalo:BAAANQAECgIIAgAAAA==.Pandalock:BAABNQAECn8UAAILAAkKjQvQLAAcAQALAAkKjQvQLAAcAQAAAA==.Parasiite:BAABNQAECn8lAAIWAAoKQRhBKwDNAQAWAAoKQRhBKwDNAQAAAA==.Parasíte:BAAANQABCggICAABNQAECgoKJQAWAEEYAA==.',
Pe='Peepocute:BAABNQAECn80AAMOAAoKbhvLEgAhAgAOAAoKbhvLEgAhAgACAAYKrwrTUgBIAQAAAA==.Peghane:BAAANQADCgQIBwAAAA==.Pelarn:BAAANQADCgUIBQAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQAECgcICwAAAA==.Physiowar:BAABNQAECn8gAAIKAAkKgRYChgANAgAKAAkKgRYChgANAgAAAA==.',
Pi='Pickledeath:BAAANQAECgQIBgAAAA==.Pilik:BAAANQABCgYIBgAAAA==.Pirozhki:BAAANQADCgcIDQAAAA==.Pizzapuff:BAAANQAECgQIBQAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECn9PAAMcAAoK1CRnAgCZAwAcAAoK1CRnAgCZAwAeAAYKMR3aDABwAQAAAA==.Popavkrovi:BAABNQAFFH8FAAISAAUK8gW0FgAwAQASAAUK8gW0FgAwAQAAAA==.Popster:BAAANQADCgYIDgAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prada:BAAANQADCgIIAgAAAA==.Prell:BAAANQAECgQICAAAAA==.Preservation:BAAANQAECgcIEgABNQAFFAUIDQAhAC0gAA==.Primrosé:BAAANQADCgUIBQABNQAECgkJHgAHAI8cAA==.Prodipriest:BAABNQAFFH8FAAIWAAMKcgnjEAC6AAAWAAMKcgnjEAC6AAAAAA==.',
Ps='Psÿko:BAAANQAECgUIBQAAAA==.',
Pu='Puffdragon:BAAANQADCgIIAgAAAA==.Pugi:BAAANQADCgEIAQAAAA==.Punkpally:BAAANQAECgUICgAAAA==.Pushstickk:BAAANQABCgMIAwABNQAECgEIAgARAAAAAA==.Putridstrike:BAAANQAECggICQABNQAECgkJLwAQAPQkAA==.',
Qt='Qtiy:BAAANQAECgUIBQABNQAECgkJMAAKAMcgAA==.Qtyy:BAABNQAECn8wAAIKAAkKxyD0KgCHAgAKAAkKxyD0KgCHAgAAAA==.',
Qu='Quantaboom:BAAANQADCgYIBgAAAA==.',
Ra='Raawwrr:BAAANQADCggIFAAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Raegyr:BAAANQADCggIDQAAAA==.Ragehound:BAAANQADCgYIBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ralphpalaa:BAAANQADCgEIAQAAAA==.Ramped:BAAANQAECgQICQAAAA==.Ranzor:BAABNQAECn8XAAIQAAoKMRezEAAdAgAQAAoKMRezEAAdAgAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgIIAgAAAA==.Raveyn:BAAANQAECgcIEQAAAA==.Ravn:BAAANQABCgIIAgAAAA==.Razzaa:BAAANQADCgcICAAAAA==.',
Re='Redjak:BAAANQADCggIEAAAAA==.Regino:BAABNQAECn8hAAMJAAcKKw30RQDYAAAVAAYKFAqJ9gDjAAAJAAUKRQ/0RQDYAAAAAA==.Reitiado:BAAANQAECgEIAQAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECgkJGwAXAFEQAA==.Rekita:BAABNQAECn8bAAIXAAkKURD6hwD7AQAXAAkKURD6hwD7AQAAAA==.Remedi:BAAANQAECgYIEwAAAA==.Resyoself:BAAANQAECgYIEQAAAA==.Retispagheti:BAAANQADCggJCAAAAA==.Retnuh:BAABNQAECn86AAIXAAoK8RM1YQDrAQAXAAoK8RM1YQDrAQAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rheiner:BAAANQADCggICAAAAA==.Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQAECgIIAgAAAA==.',
Ri='Rickoutlaw:BAAANQADCgcIBwAAAA==.Rimmjab:BAABNQAECn8UAAIGAAoKkg3zVgBrAQAGAAoKkg3zVgBrAQAAAA==.Rivén:BAAANQAECgUICAABNQAECgkJHgAHAI8cAA==.',
Rn='Rn:BAABNQAECn8WAAIhAAoKGxgWQACSAgAhAAoKGxgWQACSAgAAAA==.',
Ro='Rockypalboa:BAAANQADCgcIBwAAAA==.Roderika:BAAANQAECgQIBAABNQAFFAQIDwADAA4lAA==.Roids:BAAANQADCggIDgAAAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAABNQAECn8fAAIDAAkK9RdsOAAmAgADAAkK9RdsOAAmAgAAAA==.Romanflak:BAAANQAECgIIAwAAAA==.Roostr:BAABNQAECn8xAAITAAkKEBZ7BQCFAQATAAkKEBZ7BQCFAQAAAA==.Rord:BAABNQAECn80AAMVAAoKYyAkXwB7AgAVAAoKYyAkXwB7AgAdAAEKvxS8GwE8AAAAAA==.Rosalei:BAAANQAECggICgAAAA==.Royjacked:BAAANQAECgMIBAAAAA==.',
Ru='Rubberr:BAAANQAECgUICQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAABNQAECn8UAAIXAAkKiAnDjACBAQAXAAkKiAnDjACBAQAAAA==.Runicstrike:BAABNQAECn9UAAQDAAoKsiV9AgBfAwADAAkKdyV9AgBfAwAEAAkKSSOkDABVAwAFAAkKLhmiOACnAQABNQAECgkJLwAQAPQkAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sackakt:BAAANQADCggIDQAAAA==.Sadeye:BAAANQAECggIDAAAAA==.Sadie:BAABNQAECn8XAAISAAgK+RENiQB7AQASAAgK+RENiQB7AQABNQAECgoKOgAHABslAA==.Sagalia:BAAANQADCgIIAgABNQAECggICAARAAAAAA==.Sahra:BAABNQAECn86AAIHAAoKGyWZAwCwAwAHAAoKGyWZAwCwAwAAAA==.Sanazale:BAABNQAECn8dAAMcAAgKIB7+DQDHAgAcAAgKIB7+DQDHAgAeAAcK2h18BwAKAgABNQAECgkJIAAeAEEgAA==.Sanctustrike:BAABNQAECn8tAAQVAAoKcyPBXwB6AgAVAAoKrCHBXwB6AgAJAAcKjSDsIwDCAQAdAAMKkB06qgC4AAABNQAECgkJLwAQAPQkAA==.Sandalin:BAAANQADCgEIAQAAAA==.Saraphina:BAABNQAECn8gAAIPAAkKZApRhwCGAQAPAAkKZApRhwCGAQAAAA==.Saturosix:BAAANQADCggIEgABNQAECgYIBgARAAAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.Sayge:BAAANQABCgMIBAAAAA==.',
Se='Sellandre:BAABNQAECn8fAAMUAAoK1BUkDwCBAQAPAAkKLBJCxwD2AQAUAAcKFhQkDwCBAQAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECgoKKAAfAKkQAA==.Seronja:BAAANQAECgQIBwAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shazzai:BAABNQAECn8gAAIXAAkKqBkFhQCTAQAXAAkKqBkFhQCTAQAAAA==.Sherfight:BAABNQAECn9GAAMSAAoKOyR9BgC8AwASAAoKOyR9BgC8AwAWAAQKMxopQwAbAQAAAA==.Shielddaddy:BAAANQAECgcIDwAAAA==.Shieldsftl:BAABNQAECn8fAAIEAAgKcAztQQD0AAAEAAgKcAztQQD0AAABNQAECgkJFAALAI0LAA==.Shiftycent:BAAANQAECggIBQAAAA==.Shnyaga:BAACNQAFFH8GAAISAAQKOA0wGAAgAQASAAQKOA0wGAAgAQA1AAQKf10CBBIACgp6JskAAOkDABIACgp6JskAAOkDABYABAq0H4M3AGkBACMAAgpBFe4aAJEAAAAA.Shockybalboa:BAABNQAECn8bAAMGAAgKTAfNeQAJAQAGAAgKTAfNeQAJAQANAAEKAADBNwAwAAAAAA==.Shrider:BAAANQADCgYIEgAAAA==.Shunkd:BAAANQAECgYICwAAAA==.Shøcker:BAAANQADCgEIAQAAAA==.',
Si='Sianda:BAAANQABCgYIBwAAAA==.Silandera:BAAANQAECgEIAgAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQABNQAECggIAwARAAAAAA==.Sinsanityz:BAABNQAECn8VAAMSAAgKmhR+dwC1AQASAAcKNxd+dwC1AQAWAAIKhgJBawAJAAAAAA==.Sixxsevenn:BAAANQAECgcICwAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQAECgQIBAAAAA==.',
Sk='Skinwalk:BAABNQAECn8oAAIHAAcKHhkxPwACAgAHAAcKHhkxPwACAgAAAA==.Skrai:BAAANQAECgQIBQAAAA==.',
Sl='Slackerftw:BAAANQAECgEIAQAAAA==.Slamhog:BAAANQAECgYIBQABNQAECgoKNwAdAJshAA==.Sleew:BAABNQAECn83AAMhAAoK8BygPgCXAgAhAAkKbxygPgCXAgATAAIKYRULTwCSAAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.Slixer:BAAANQAECgIIBAAAAA==.',
Sm='Smokintrees:BAAANQAECgYICwAAAA==.Smorkchop:BAAANQAECgIIAgAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQAECgYIDAAAAA==.',
So='Soggypringle:BAAANQAECgEIAQAAAA==.Solary:BAAANQADCgIIAgAAAA==.Solnath:BAABNQAECn8yAAICAAoKtyOcBwCAAwACAAoKtyOcBwCAAwAAAA==.Sorcha:BAAANQADCgMIAwAAAA==.Souldaddy:BAABNQAECn8VAAIPAAcKNgNY5wDMAAAPAAcKNgNY5wDMAAAAAA==.',
Sp='Spankinstien:BAAANQAECgcICQAAAA==.Specsdraco:BAACNQAFFH8IAAIiAAUKfQ2RFgDXAAAiAAUKfQ2RFgDXAAA1AAQKfzgAAiIACgq8I1wDAKUDACIACgq8I1wDAKUDAAAA.Spewpuke:BAACNQAFFH8FAAMKAAMKtAlfKAB7AAAKAAMKZwJfKAB7AAAQAAEKHhvCBgBQAAA1AAQKf1kAAxAACgqZIwoCADQDABAACgqZIwoCADQDAAoACQrPEOWHAAgCAAAA.Spicytomato:BAABNQAECn9EAAQfAAoK7yFlAQBKAwAfAAoK7yFlAQBKAwAhAAIKdyB/+ABUAAATAAIKxxkGKQBSAAAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAACNQAFFH8GAAISAAIKqA3kKQB+AAASAAIKqA3kKQB+AAA1AAQKfzkAAhIACgpZF34qAIwCABIACgpZF34qAIwCAAAA.Starstorm:BAAANQADCgQIBAABNQAECgoKNwAhAPAcAA==.Stgermain:BAACNQAFFH8GAAISAAQKnRaVGAAcAQASAAQKnRaVGAAcAQA1AAQKfzMAAxIACgpYHgApAMUCABIACgpYHgApAMUCABYABwq2FMIzAIUBAAAA.Stinkybinks:BAAANQAECgUIBQAAAA==.Stormlotus:BAAANQAECgMICwAAAA==.Stormsorrow:BAABNQAECn8WAAMOAAYKngkzRwAbAQAOAAYKngkzRwAbAQABAAEKAACCOgAXAAAAAA==.Strawberry:BAEANQADCggICQABNQAECgoKJwAaADkQAA==.Strikeanywer:BAAANQAECgQIDQAAAA==.',
Su='Summers:BAAANQAECgMIAgAAAA==.Superstoned:BAAANQAECgEIAQAAAA==.Surudk:BAAANQAECgYICgAAAA==.',
Sy='Sylrana:BAAANQAECgcIEgAAAA==.Sylri:BAAANQAECgQIBAAAAA==.Sylvie:BAAANQAECgYICQABNQAECgoKOgAHABslAA==.',
Ta='Takticel:BAAANQAECgUICwAAAA==.Taktikal:BAAANQADCggICAABNQAECgUICwARAAAAAA==.Taktikell:BAAANQADCgYIBgABNQAECgUICwARAAAAAA==.Taktikil:BAAANQAECgMIAgABNQAECgUICwARAAAAAA==.Talizar:BAAANQADCgEIAQAAAA==.Talrad:BAAANQAECggIEAAAAA==.Tauralyon:BAABNQAECn8bAAIdAAkKnRtNLABkAgAdAAkKnRtNLABkAgABNQAECgkJHQAHAPwdAA==.Tazerxface:BAACNQAFFH8JAAIHAAQKhROmEwAIAQAHAAQKhROmEwAIAQA1AAQKf1YAAgcACgpXHhkRACEDAAcACgpXHhkRACEDAAAA.Tazlmao:BAAANQAECgQIBQAAAA==.',
Te='Tealgos:BAABNQAECn8eAAIeAAYKVAvPIgAyAQAeAAYKVAvPIgAyAQAAAA==.Teenyhands:BAABNQAECn8hAAMUAAgK/glTFQAnAQAUAAgK/glTFQAnAQAPAAUKEwHAqQFuAAAAAA==.Teirlily:BAAANQADCgUIBQABNQAECgkJHgAHAI8cAA==.Teldrasa:BAAANQAECgQIBQAAAA==.Telerein:BAAANQAECgUICQAAAA==.Teucer:BAAANQAECgMIAwAAAA==.Tewtz:BAAANQADCgQIBAAAAA==.',
Th='Thaiddous:BAABNQAECn82AAIgAAoKNh9ABwATAwAgAAoKNh9ABwATAwAAAA==.Thanx:BAAANQAECgQICAAAAA==.Thealphabear:BAAANQAECgQIDAAAAA==.Thebeefchief:BAACNQAFFH8TAAIgAAYKQR2vAACdAQAgAAYKQR2vAACdAQA1AAQKfygAAiAACgqbIzIFAEsDACAACgqbIzIFAEsDAAAA.Thebigmon:BAABNQAECn8/AAIGAAoKDR4yKwDTAgAGAAoKDR4yKwDTAgAAAA==.Thedabara:BAAANQADCgQIBgAAAA==.Thedon:BAABNQAECn8UAAMXAAYKxgOE7QAmAQAXAAYKxgOE7QAmAQAiAAEKCwNMngAgAAAAAA==.Thelistria:BAAANQADCgUIBQAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgcICwAAAA==.Thorxx:BAAANQAECgEIAQAAAA==.Thrudtotems:BAAANQAECggIDwAAAA==.Thrudx:BAABNQAECn8iAAMdAAoK9Rb3QwBVAgAdAAoK9Rb3QwBVAgAVAAIKphDoaAF4AAAAAA==.Thugnastie:BAABNQAECn8jAAIGAAgKBguEbwAjAQAGAAgKBguEbwAjAQAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tickeld:BAAANQADCgIIAgAAAA==.Tika:BAABNQAECn85AAIUAAoKRxvlBQBeAgAUAAoKRxvlBQBeAgAAAA==.Timeisdruid:BAAANQAECgQIBAAAAA==.Tinytina:BAAANQAECgcIEAAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAABNQAECn8gAAIlAAkKpRWJCwC6AQAlAAkKpRWJCwC6AQAAAA==.Togashi:BAABNQAECn8xAAILAAkKoSARCwCiAgALAAkKoSARCwCiAgAAAA==.Toof:BAAANQAECgUIEAAAAA==.Topacio:BAABNQAECn8ZAAIgAAgKEQ1aJgA8AQAgAAgKEQ1aJgA8AQAAAA==.Topnacho:BAAANQADCgEIAQABNQAFFAgIGgAXAL8YAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAABNQAECn8lAAMIAAcK0ANMCACfAAAPAAcK0AO0UQEIAQAIAAUK6QFMCACfAAAAAA==.Totesschnook:BAAANQAECggIBgAAAA==.Toymueto:BAAANQAECgUICQAAAA==.',
Tr='Treespirit:BAABNQAECn8gAAInAAoKjB7ODgDnAgAnAAoKjB7ODgDnAgAAAA==.Trenbologne:BAAANQADCgMIAwAAAA==.Trend:BAAANQAECgUIBgAAAA==.Tricep:BAAANQADCggIGAAAAA==.Tripallie:BAAANQAECgEIAQAAAA==.Trishian:BAAANQAECgEIAQAAAA==.Tristis:BAAANQAECgQIBAAAAA==.Troco:BAAANQADCgQIBAAAAA==.Trunkmuffin:BAAANQAECgEIAgAAAA==.Truthless:BAECNQAFFH8KAAIdAAQKrBkLDwA4AQAdAAQKrBkLDwA4AQA1AAQKfysAAh0ACgqgH1APAFEDAB0ACgqgH1APAFEDAAAA.',
Tu='Tuckermax:BAAANQAECgMIBQAAAA==.Tuckser:BAAANQAECgMIAwAAAA==.Tunks:BAAANQAECgYIDwAAAA==.Tusk:BAABNQAECn8dAAIHAAkK/B0bNQCLAgAHAAkK/B0bNQCLAgAAAA==.',
Tw='Twinstar:BAAANQAECgYIBgAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECgoKTwAcANQkAA==.',
Ug='Uglyashell:BAAANQAECgEIAgAAAA==.',
Un='Unit:BAABNQAECn8oAAINAAkKCyPJCwC0AgANAAkKCyPJCwC0AgAAAA==.',
Uv='Uva:BAABNQAECn8eAAIkAAgKKBPLBgCsAQAkAAgKKBPLBgCsAQAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAABNQAECn8sAAIfAAkK8xGbBgBCAgAfAAkK8xGbBgBCAgAAAA==.Valsorin:BAAANQAECgQICQAAAA==.Valtaea:BAACNQAFFH8FAAIPAAQK9AZSKQDBAAAPAAQK9AZSKQDBAAA1AAQKf0QAAg8ACgqyE8dMABoCAA8ACgqyE8dMABoCAAAA.',
Ve='Velanthos:BAAANQAECgEIAQAAAA==.Velour:BAAANQAECgMIBQAAAA==.Vershammy:BAAANQAECgEIAQAAAA==.',
Vi='Viciouslock:BAAANQADCgMIAwAAAA==.Vigilus:BAAANQADCggICAAAAA==.Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQJBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgUIDgARAAAAAA==.Voidwaffle:BAAANQADCgcIDQAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Volrog:BAAANQADCgQIBAAAAA==.Voreah:BAAANQAECgUICQABNQAECggIFAAWAEkLAA==.',
Wa='Waarsêer:BAAANQADCgcIBwAAAA==.Wafflxs:BAACNQAFFH8LAAIbAAYKLyH4AQAiAgAbAAYKLyH4AQAiAgA1AAQKfzMAAhsACgpmJHgDAHoDABsACgpmJHgDAHoDAAAA.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAABNQAECn8jAAIVAAoKyBiedwA9AgAVAAoKyBiedwA9AgAAAA==.Warglave:BAABNQAECn8aAAICAAoKSQ0qMwBrAQACAAoKSQ0qMwBrAQAAAA==.Warmo:BAAANQAECgUIBwAAAA==.Warunk:BAABNQAECn8mAAIiAAkKjB2QBgDaAgAiAAkKjB2QBgDaAgAAAA==.',
Wc='Wcldragon:BAAANQADCgUIBgAAAA==.',
We='Weakdog:BAAANQAECgMIAwAAAA==.Weiwu:BAACNQAFFH8dAAILAAYKjBJUBgAfAQALAAYKjBJUBgAfAQA1AAQKfz4AAgsACgorIDMPAPACAAsACgorIDMPAPACAAAA.Wellfookthat:BAABNQAECn9CAAIHAAoKlyHfDQBSAwAHAAoKlyHfDQBSAwAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECgoKQgAHAJchAA==.',
Wh='Whiteshadows:BAABNQAECn8mAAIVAAkK4Rb1dgA/AgAVAAkK4Rb1dgA/AgAAAA==.Whyvala:BAAANQAECgYIEAABNQADCggILgARAAAAAA==.Whyvara:BAAANQADCggILgAAAA==.',
Wi='Wiisp:BAABNQAECn86AAIoAAoK8h78BAC/AgAoAAoK8h78BAC/AgAAAA==.',
Wo='Wolneyd:BAAANQAECgYIBQABNQAFFAIIBwAVABwkAA==.Wolnney:BAACNQAFFH8HAAIVAAIKHCS+FgDIAAAVAAIKHCS+FgDIAAA1AAQKf2IAAhUACgpmJiIDAHwDABUACgpmJiIDAHwDAAAA.Wowimhealing:BAAANQADCgcIEAAAAA==.',
Wr='Wrath:BAAANQADCgQIBAAAAA==.',
Wu='Wubnah:BAAANQADCgIIAwAAAA==.',
['Wâ']='Wâarseer:BAAANQAECgQIBQAAAA==.',
Xa='Xairo:BAAANQAECgUIBgAAAA==.Xalatoes:BAACNQAFFH8eAAIHAAgKexq/BQAPAgAHAAgKexq/BQAPAgA1AAQKfzEAAgcACgquHzQeAPMCAAcACgquHzQeAPMCAAAA.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.',
Xi='Xionglieren:BAAANQADCgQIBAABNQAECgUICAARAAAAAA==.Xiren:BAAANQABCgQIBwAAAA==.',
Xr='Xraiz:BAABNQAECn8lAAIgAAoKTA9VHgB6AQAgAAoKTA9VHgB6AQAAAA==.',
Xy='Xyne:BAAANQADCggIEQAAAA==.',
Ya='Yahaloser:BAAANQADCgMIAwAAAA==.Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAACNQAFFH8SAAIbAAUKaR4nAwDWAQAbAAUKaR4nAwDWAQA1AAQKf04AAhsACgp/JJACAJQDABsACgp/JJACAJQDAAAA.Yourboyblue:BAAANQADCgYIHAAAAA==.Yourmaster:BAABNQAECn8dAAMnAAgKBhItIgDJAQAnAAgKBhItIgDJAQAmAAUK0gCfsAA1AAAAAA==.',
Yu='Yunna:BAAANQADCggICgAAAA==.',
Yv='Yverrius:BAAANQADCgMICAAAAA==.',
Za='Zanydruid:BAAANQADCgQICQAAAA==.Zanza:BAABNQAECn8cAAIKAAoKphV2RwAZAgAKAAoKphV2RwAZAgAAAA==.Zariana:BAAANQAECgIICAAAAA==.Zarione:BAAANQAECgMIBAAAAA==.',
Ze='Zemus:BAAANQADCggIEQAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.Zepbound:BAAANQABCggIFgAAAA==.Zethrak:BAAANQAECgEIAQAAAA==.',
Zh='Zhamazu:BAAANQADCgUIBwAAAA==.Zharost:BAAANQADCggIDgAAAA==.Zhayden:BAABNQAECn8WAAIaAAcKOhf0GwD2AQAaAAcKOhf0GwD2AQAAAA==.Zhy:BAAANQAECgMIAwAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.Zidenko:BAAANQAECgQIBgAAAA==.',
Zo='Zodin:BAAANQAECgMIBAABNQAECggIDAARAAAAAA==.Zombiez:BAABNQAECn8iAAIEAAkKuQgbMQBRAQAEAAkKuQgbMQBRAQAAAA==.Zoov:BAAANQAECggIDAAAAA==.Zoryn:BAAANQAECgQIBgABNQADCggICAARAAAAAA==.',
Zu='Zumalee:BAAANQAECggICAAAAA==.',
Zw='Zwerlin:BAAANQAECgEIAgAAAA==.',
['Âb']='Âbaddön:BAAANQADCgYICwAAAA==.',
['Él']='Élowen:BAAANQAECgIIAwAAAA==.',
['ßi']='ßirdmân:BAABNQAECn8vAAIVAAoKph4sTACwAgAVAAoKph4sTACwAgAAAA==.',
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
