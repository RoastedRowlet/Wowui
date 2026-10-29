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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Mage-Fire','Paladin-Protection','Warrior-Arms','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement','Mage-Arcane','Warrior-Protection','Unknown-Unknown','Warlock-Destruction','Mage-Frost','Paladin-Retribution','Priest-Shadow','Rogue-Subtlety','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Paladin-Holy','DemonHunter-Devourer','Warlock-Affliction','Priest-Holy','Druid-Guardian','Warlock-Demonology','Hunter-Marksmanship','Evoker-Devastation','Priest-Discipline','Hunter-Survival','Warrior-Fury','Druid-Balance','Evoker-Preservation','Druid-Restoration','Druid-Feral','Evoker-Augmentation',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaradh:BAABNQAECn8lAAMBAAoKbgi+FwA0AQABAAoKbgi+FwA0AQACAAEKqQOpnwAfAAAAAA==.Aaradk:BAABNQAECn8mAAMDAAoKHw1pWACRAQADAAoKHw1pWACRAQAEAAEKRQOx+AAfAAABNQAECgoKJQABAG4IAA==.Aarahunt:BAAANQAECgYICgABNQAECgoKJQABAG4IAA==.',
Ab='Abaddondk:BAABNQAECn8wAAIFAAkKXBQNHQDjAQAFAAkKXBQNHQDjAQAAAA==.Abilify:BAAANQABCgcIJAAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Aces:BAABNQAECn8ZAAMGAAkKPAontgABAQAGAAgKuAYntgABAQAHAAkKTAjgXQDzAAAAAA==.Acez:BAAANQAECggIEAABNQAECgkJGQAGADwKAA==.Acidwaste:BAAANQADCggIHAAAAA==.',
Ad='Addilynn:BAABNQAECn8VAAICAAUKpAEBggBvAAACAAUKpAEBggBvAAAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAABNQAECn86AAIIAAoKQxS3AQCBAgAIAAoKQxS3AQCBAgAAAA==.',
Ae='Aelania:BAABNQAECn8VAAIJAAcKoRGrIAD2AAAJAAcKoRGrIAD2AAAAAA==.Aelunara:BAABNQAECn8gAAMEAAcKBhe/VAC/AQAEAAcKBhe/VAC/AQADAAEKAABzzgAvAAAAAA==.Aemoz:BAAANQAECgQJBAAAAA==.Aerthalis:BAAANQADCgIIAgAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgYIDQAAAA==.',
Ai='Ailric:BAAANQAECgYIDAAAAA==.Ainke:BAAANQADCgYICgAAAA==.',
Al='Alarakian:BAABNQAECn8aAAIKAAoKVBN9MQARAgAKAAoKVBN9MQARAgAAAA==.Alexei:BAABNQAECn8pAAMLAAgK0RZ6FgCIAQALAAgK0RZ6FgCIAQAMAAcK1A1THQATAQAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAABNQAECn8gAAQHAAoKoA08cgDKAQAHAAkK5ws8cgDKAQAGAAUKehD7qwAZAQANAAIK3QP6MQBWAAAAAA==.Alkhan:BAABNQAECn8jAAICAAcKdwc3OQDtAAACAAcKdwc3OQDtAAABNQAECgoKOgAOAP4RAA==.Allymage:BAAANQADCgMIAwAAAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altoids:BAAANQAECgUIDAAAAA==.Altos:BAACNQAFFH8LAAMPAAQKAQXvBQCVAAAPAAQKAQXvBQCVAAAKAAEKAAAQLgAAAAA1AAQKfzcAAg8ACgrsFSoPADkCAA8ACgrsFSoPADkCAAAA.Altóids:BAAANQAECgQIBAABNQAECgUIDAAQAAAAAA==.Alwayshazy:BAAANQADCgUIBQAAAA==.Alyssachik:BAAANQAECgYIDgAAAA==.',
Am='Amdabear:BAAANQADCgcIDAAAAA==.',
An='Anartik:BAAANQAECggIBAAAAA==.Anavar:BAAANQADCgYIDwAAAA==.Angerclaw:BAAANQAECgcIDAAAAA==.Animeow:BAAANQAFFAQIAgAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.Annaalista:BAAANQABCgYIDQAAAA==.Annasun:BAAANQADCgUIBQABNQAECggIIwARANERAA==.',
Ap='Apoth:BAAANQAECgcICAABNQAECggIDgAQAAAAAA==.Apothe:BAAANQAECgUIBQABNQAECggIDgAQAAAAAA==.Apotheke:BAAANQAECggIDgAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQAECgEIAQAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAABNQAECn8fAAIOAAkKfxXitwAUAgAOAAkKfxXitwAUAgAAAA==.Arcanofrosty:BAABNQAECn8YAAMSAAYKewbaHACJAAAOAAYK0QHjggG+AAASAAUKswfaHACJAAAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAABNQAECn8uAAITAAoKyxWyQAD5AQATAAoKyxWyQAD5AQAAAA==.',
Au='Aurochi:BAAANQAECgIIAgAAAA==.',
Av='Avastin:BAAANQAECgEIAQAAAA==.',
Aw='Awni:BAABNQAECn8rAAIKAAkKYxY2eAAuAgAKAAkKYxY2eAAuAgAAAA==.',
Ba='Bacon:BAABNQAECn81AAIUAAoKSg63JAAKAgAUAAoKSg63JAAKAgAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAABNQAECn8YAAIOAAkKKh/CpwAyAgAOAAkKKh/CpwAyAgAAAA==.Baknow:BAAANQAECgIIAwAAAA==.Bambuu:BAAANQABCggIDAAAAA==.Bangbangji:BAAANQAECgUICgABNQAECgoKQgAVAOkhAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAABNQAECn8XAAIOAAcKPw3bBwGAAQAOAAcKPw3bBwGAAQAAAA==.Bartholomeow:BAAANQADCgQIBAAAAA==.Basch:BAAANQABCgYIDAAAAA==.Battlebeats:BAAANQADCgUIBQAAAA==.Bazzoo:BAAANQAECggIDQAAAA==.',
Be='Beachbabe:BAAANQADCgcIBwAAAA==.Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAABNQAECn81AAIWAAoKRB2yFgCfAgAWAAoKRB2yFgCfAgAAAA==.Benzos:BAABNQAECn8xAAQXAAoKmiR8CwAtAwAXAAkKmiR8CwAtAwAYAAgKQCGiBAC/AgAVAAEKAAAQtAAAAAAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bethezar:BAAANQAECgcICgAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAABNQAECn8/AAIZAAoKyxoxBwB3AgAZAAoKyxoxBwB3AgAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgUIDgAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQAECgUIDQAAAA==.',
Bl='Bluerose:BAAANQAECgQIDgAAAA==.Blurry:BAABNQAECn8jAAIRAAgK0REZDAA2AgARAAgK0REZDAA2AgAAAA==.',
Bo='Boltsandhoes:BAAANQADCggICAABNQAECgcIEQAQAAAAAA==.Boomidk:BAAANQAECgMIAwAAAA==.Bountmage:BAABNQAECn8XAAISAAYKkxVBFQBYAQASAAYKkxVBFQBYAQAAAA==.Bovinnie:BAAANQAECgMIAwAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brillectra:BAAANQAECgMIAQAAAA==.Brisketboy:BAAANQADCgQJBAAAAA==.Bro:BAAANQAECgUIDgAAAA==.Brokentuskz:BAAANQAECggJAQABNQAECgkJMAAFAFwUAA==.Bronthos:BAAANQADCggICAAAAA==.Brothertunks:BAAANQADCgMIAwAAAA==.Brêwski:BAAANQAECgIIAgAAAA==.',
Bu='Budago:BAAANQAECgUICAABNQAECgcIEwAQAAAAAA==.Buffbutton:BAABNQAECn8iAAIOAAgKkQ2RbwBnAQAOAAgKkQ2RbwBnAQABNQAECgoKOgAKAKIaAA==.Buffstallion:BAAANQAECgMIBwAAAA==.Buzzie:BAAANQADCgcIDwAAAA==.',
['Bï']='Bïllï:BAABNQAECn8rAAIHAAoKyh9+GQAwAwAHAAoKyh9+GQAwAwAAAA==.',
Ca='Caerisma:BAAANQAECggILAAAAQ==.Cakevswaffle:BAAANQAECggIAQAAAA==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Celestino:BAAANQADCgIIAgAAAA==.Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Chainevoker:BAAANQAECgcIDAAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQAECgYIBgABNQAECggILAAQAAAAAQ==.Chiang:BAAANQADCggICAAAAA==.Chlena:BAAANQAFFAQIBAAAAA==.Chudmax:BAAANQADCgYIDQAAAA==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUJBgAAAA==.',
Cl='Clegen:BAAANQADCggICwAAAA==.Cloax:BAACNQAFFH8GAAIUAAIKSxiXCQCuAAAUAAIKSxiXCQCuAAA1AAQKfzoAAhQACgrgH8QMAB4DABQACgrgH8QMAB4DAAAA.Cláp:BAABNQAFFH8HAAIPAAcK6xUxAQDrAQAPAAcK6xUxAQDrAQAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAEANQADCggIDgABNQAECggIDgAQAAAAAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Conquerlock:BAAANQAECgMIAwAAAA==.Coobibrains:BAAANQADCgUIBwAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCggIDQAAAA==.Cory:BAAANQADCgIIAgAAAA==.',
Cr='Craerman:BAAANQADCgYICwABNQAECggILAAQAAAAAQ==.Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Creella:BAAANQABCgcICwAAAA==.Cryhavok:BAACNQAFFH8GAAMTAAIKNAzHGACFAAATAAIKNAzHGACFAAAaAAEKzQGJLwA1AAA1AAQKfzYAAxMACgrZG6swADgCABMACgrZG6swADgCABoAAgquDsIAAXkAAAAA.',
Cu='Cussack:BAABNQAECn8sAAIKAAoKyiLyHABEAwAKAAoKyiLyHABEAwAAAA==.Cutepandaa:BAAANQADCgQIBAAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgoKQgAVAOkhAA==.Daghar:BAAANQAECgIJAwAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQAECgcIEwAAAA==.Danui:BAAANQADCgQIBAAAAA==.Darkgol:BAABNQAECn8UAAIKAAYKlArGigD7AAAKAAYKlArGigD7AAABNQAECgkJKAATAEwPAA==.Darkshayd:BAAANQADCgIIAgAAAA==.Davioon:BAAANQAECgIIBQAAAA==.Dayrb:BAAANQAECgQIBQAAAA==.',
Db='Dblade:BAAANQAFFAQIBAAAAA==.',
De='Deadlyheal:BAAANQAECgEIAQABNQADCggICAAQAAAAAA==.Deadtalini:BAACNQAFFH8GAAMFAAMKiwncDwB5AAAFAAIKiwncDwB5AAADAAEKAAB/JwAAAAA1AAQKfzgAAwUACgq+HnoYAMYCAAUACgpmGnoYAMYCAAMACgrFGgs5ACICAAAA.Deah:BAABNQAECn8ZAAIWAAgKRCAHGACWAgAWAAgKRCAHGACWAgAAAA==.Deaththroes:BAAANQAECgQIBQAAAA==.Deckerdramon:BAABNQAECn86AAIPAAoKjxqxBQAtAgAPAAoKjxqxBQAtAgAAAA==.Demomachin:BAABNQAECn8vAAIBAAoK0hloBAAQAgABAAoK0hloBAAQAgAAAA==.Demonnoodle:BAAANQADCggICQABNQAECgcIFwAIAKwQAA==.Demonsfear:BAABNQAECn8lAAIbAAoKwBfMGQCLAgAbAAoKwBfMGQCLAgAAAA==.Demyze:BAAANQADCggIEAAAAA==.Densetsu:BAAANQADCgcJBwAAAA==.Destroyera:BAAANQAECgUIBgAAAA==.Deucalyon:BAAANQADCggIJAAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devourme:BAAANQAECgMIAgABNQAFFAYIGAAGABQcAA==.Devours:BAACNQAFFH8YAAIGAAYKFBw6CwCZAQAGAAYKFBw6CwCZAQA1AAQKfywAAgYACgriHPgvAKICAAYACgriHPgvAKICAAAA.Devuledegg:BAAANQADCgEIAQAAAA==.',
Di='Dirtyhooves:BAAANQADCggIDwABNQAECgMIBAAQAAAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAACNQAFFH8ZAAIZAAcKKyatAACOAgAZAAcKKyatAACOAgA1AAQKfzMAAhkACgr0JiIAAAEEABkACgr0JiIAAAEEAAAA.',
Do='Doesdrool:BAAANQADCgEIAQAAAA==.Dohtem:BAAANQADCgYICwABNQAECgkJIwANAM4cAA==.Donmegah:BAAANQAECgUIDgAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Draemon:BAAANQADCgEIAQAAAA==.Dragapult:BAAANQAECggIDwABNQAFFAQIDwADAA4lAA==.Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Dragusysmash:BAAANQAECgEIAQAAAA==.Draki:BAAANQADCgYIEAAAAA==.Drazzin:BAAANQADCgEIAQABNQAECgoKIQAcACwQAA==.Dredtotem:BAAANQAECgQIBAAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Durzaxda:BAAANQADCgUIBQAAAA==.Dusky:BAAANQABCgYICgAAAA==.Dutanu:BAAANQAECgUICQABNQAECgkJLwATANIeAA==.',
['Dö']='Dötcom:BAAANQADCgYICAAAAA==.',
Ec='Echpochmak:BAABNQAECn8YAAIdAAgKgCN3DwD3AgAdAAgKgCN3DwD3AgAAAA==.',
Ei='Eibhlean:BAABNQAECn8rAAIJAAkKhRTrEgB4AQAJAAkKhRTrEgB4AQABNQAECgQICQAQAAAAAA==.Eireckt:BAAANQADCgcIDAAAAA==.Eirrin:BAAANQAECggIEwAAAA==.Eivorr:BAAANQABCgQJAgAAAA==.',
El='Elariin:BAABNQAECn8fAAMGAAcKQxzSawDIAQAGAAYKQxzSawDIAQAHAAQKGgz4gQCaAAAAAA==.Elaril:BAAANQADCgcIFAAAAA==.Eleforever:BAACNQAFFH8FAAIHAAIK4BpAIQCoAAAHAAIK4BpAIQCoAAA1AAQKfzkAAgcACgowIv4VAEUDAAcACgowIv4VAEUDAAAA.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcIBwAAAA==.Elleredreaux:BAAANQAECggICgAAAA==.',
Em='Emongar:BAAANQAECgQIBQAAAA==.',
En='Endomorphism:BAAANQAECgIIAgABNQAFFAcIGAAeAP4gAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ev='Eveldumboone:BAAANQAECgIIAgABNQAFFAUIEgAeAIIeAA==.Evlynia:BAAANQADCgMIAgAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAABNQAECn8lAAIfAAgKERKJgADlAQAfAAgKERKJgADlAQAAAA==.',
Fa='Fableshoot:BAAANQAECgUIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgAQAAAAAA==.Fangtang:BAAANQAECggICAAAAA==.Fantasie:BAAANQAECgEIAQABNQAECgoKPwAdADskAA==.Fatherclutch:BAAANQADCgQICAABNQAECggIFwAMANAMAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAACNQAFFH8FAAIWAAIKXg1yGACQAAAWAAIKXg1yGACQAAA1AAQKfzcAAxYACgohH1sZAI4CABYACgohH1sZAI4CACAAAwreCCNnAI8AAAAA.',
Fe='Fearfactor:BAAANQADCgQIBAAAAA==.Felpal:BAAANQABCgMIAQABNQAECgYIHgAhAFQLAA==.Felwoof:BAABNQAECn8xAAQcAAoKOCEUBADFAQAcAAcKXCEUBADFAQAfAAUKTB7RmgCkAQARAAIKMxykEgCFAAAAAA==.Felzak:BAAANQADCgYIBgABNQAECgQIBgAQAAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgYIEAAAAA==.Fistachio:BAAANQADCggIDgAAAA==.',
Fl='Flarllek:BAAANQADCgQIDgAAAA==.Flexxed:BAABNQAECn8jAAIFAAkKhyHgFgDUAgAFAAkKhyHgFgDUAgAAAA==.Florin:BAAANQAECgEIAQAAAA==.',
Fo='Foopz:BAAANQADCgIJAgABNQAECgEIAQAQAAAAAA==.Forthehordde:BAAANQABCgcICwAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Freddybones:BAAANQAECgEIAgAAAA==.Friendlytwo:BAAANQADCggIDgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgQIBgABNQAECgoKPwAdADskAA==.Frostyduggo:BAABNQAECn8qAAISAAcKKg2jFgBIAQASAAcKKg2jFgBIAQAAAA==.Frostyxz:BAAANQADCgQIBAAAAA==.Fry:BAACNQAFFH8YAAIUAAcKARN3BQDgAQAUAAcKARN3BQDgAQA1AAQKfykAAhQACgp5H5QWAKcCABQACgp5H5QWAKcCAAAA.Fríeren:BAAANQADCgIIAgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgYIEAAAAA==.Fumblemore:BAAANQADCgEIAQAAAA==.Furystrike:BAABNQAECn8sAAMPAAkKYCNkBgAAAwAPAAkK5SJkBgAAAwAKAAkKsxzGQwC+AgABNQAECgoKLAATAHMjAA==.Futbuckmcgee:BAAANQADCggICAAAAA==.',
Ga='Galixie:BAAANQABCgQIBgAAAA==.Ganondrow:BAABNQAECn82AAQUAAoKkCKnBQDIAgAUAAoKkCKnBQDIAgAdAAMKqhrmtAD4AAAiAAEKng6XJgA8AAAAAA==.',
Ge='Gehagnute:BAAANQADCgEIAQAAAA==.Gemelo:BAABNQAECn8fAAIjAAoKSROlBACfAQAjAAoKSROlBACfAQAAAA==.Geromul:BAAANQAECgYIBgAAAA==.Gerrexs:BAABNQAECn8UAAIKAAgKNBA9swCdAQAKAAgKNBA9swCdAQAAAA==.',
Gi='Gibayy:BAABNQAECn8XAAIOAAYKXCGpsgAeAgAOAAYKXCGpsgAeAgAAAA==.Gibsonex:BAAANQAECgYIDAAAAA==.Gideone:BAAANQADCgYICgAAAA==.Gildagni:BAAANQAECgMIAwAAAA==.Gilliamm:BAABNQAECn84AAMVAAoK8hOWIwCsAQAVAAcKmBWWIwCsAQAXAAUKgBFrWgBPAQAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Gn='Gnorman:BAAANQADCgIIAgAAAA==.',
Go='Golath:BAABNQAECn8oAAITAAkKTA+znwDiAQATAAkKTA+znwDiAQAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAABNQAECn8YAAIWAAgKzQMVoADvAAAWAAgKzQMVoADvAAAAAA==.Gothbutta:BAAANQAECgQICAAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Grandena:BAAANQADCgUICgAAAA==.Graydeon:BAAANQAECgcIDQAAAA==.Greatangel:BAAANQADCgUIBAABNQAECggIIwARANERAA==.Gregano:BAAANQAECgUIBAABNQAECgkJHgAKACkMAA==.Gregorian:BAABNQAECn8eAAIKAAkKKQwBqQC2AQAKAAkKKQwBqQC2AQAAAA==.Gremliin:BAACNQAFFH8JAAIdAAQK+ROJDwAzAQAdAAQK+ROJDwAzAQA1AAQKfzwAAh0ACgq9HXoWAB8DAB0ACgq9HXoWAB8DAAAA.Gremliinss:BAAANQAECgcIBwAAAA==.Gretch:BAAANQADCggIDQAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Ha='Hadesdecends:BAAANQADCgMIAwAAAA==.Halakal:BAAANQAECgQIBgAAAA==.Hammerbell:BAAANQAECggJCAAAAA==.Haviboomer:BAAANQAECgQICAAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.Haywardlol:BAAANQAECggICAAAAA==.',
He='Healmeharder:BAAANQADCgIIAgAAAA==.Healminth:BAAANQAFFAQIAgAAAA==.Healthcare:BAAANQAECgIIAgAAAA==.Hethar:BAAANQAECgEIAQAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hightide:BAAANQAECgYICwAAAA==.Hippo:BAAANQAECgYIEAAAAA==.',
Ho='Hoja:BAAANQAECgYIBwAAAA==.Holdor:BAAANQADCgUIBgAAAA==.Holdors:BAAANQADCggIDAAAAA==.Holier:BAAANQADCgYIBgABNQADCggJCAAQAAAAAA==.Holybloodboi:BAAANQAECgEJAQABNQAECgoKJgAGAKUkAA==.Holybuns:BAAANQADCggIDQAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIBQABNQAECgcIFwAIAKwQAA==.',
Ht='Htilogak:BAAANQAECgMIAwAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAABNQAECgYIBwAQAAAAAA==.',
Ic='Iceberg:BAAANQADCgYIBgAAAA==.Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQAECgMIAwAAAA==.',
In='Insanegrippy:BAAANQAECgYICgABNQAFFAcIHAAGANQdAA==.Intaria:BAACNQAFFH8FAAIKAAMKugPrGACYAAAKAAMKugPrGACYAAA1AAQKfysAAwoACgqlFCl0ADgCAAoACgpwFCl0ADgCACQAAwpDFHoiAKMAAAAA.Invisibulity:BAAANQADCgYICQABNQAECgYIHgAhAFQLAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgMIAgAAAA==.Itsrambo:BAABNQAECn8YAAITAAoKNBS4XwCbAQATAAoKNBS4XwCbAQAAAA==.',
Ja='Jackbeef:BAACNQAFFH8GAAIkAAIKLBp4AQCUAAAkAAIKLBp4AQCUAAA1AAQKfy8AAiQACgpNIR8DAC8DACQACgpNIR8DAC8DAAAA.Jadedhooves:BAABNQAECn8pAAITAAcKiRC3mQAgAQATAAcKiRC3mQAgAQAAAA==.Jaggedlilhun:BAABNQAECn8nAAIWAAkKxQ+PYQB7AQAWAAkKxQ+PYQB7AQAAAA==.Jaggedshammy:BAABNQAECn8UAAIHAAYK0wmvYADrAAAHAAYK0wmvYADrAAABNQAECgkJJwAWAMUPAA==.Jagruk:BAAANQADCgIIAgABNQAECgQIBgAQAAAAAA==.Jak:BAAANQADCgUIBQAAAA==.Jareyk:BAABNQAECn8zAAMaAAoKMBrfQgBZAgAaAAoKMBrfQgBZAgATAAEKAACKdQEAAAAAAA==.Jarladorin:BAAANQAECgIIAgABNQAECgkJGQAKAKcPAA==.Jarlu:BAAANQAECggICgAAAA==.Jaxodk:BAABNQAECn8mAAMEAAkK+CEdFgAKAwAEAAgKqiIdFgAKAwAFAAkKlR4eIQCEAgAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jecka:BAAANQAECgEIAgAAAA==.Jecynth:BAAANQADCgIIAgAAAA==.Jedai:BAACNQAFFH8NAAIaAAUK8RMSCAB0AQAaAAUK8RMSCAB0AQA1AAQKf0IAAhoACgq0IKwKAB0DABoACgq0IKwKAB0DAAAA.Jellybeann:BAAANQADCgUIDgAAAA==.Jerrysix:BAABNQAECn8kAAMUAAkKfROlKQDbAQAUAAgK/hSlKQDbAQAiAAcKOBMFDQBlAQAAAA==.Jerrytwo:BAAANQAECgQIBgAAAA==.',
Ji='Jilseponie:BAAANQABCgIIAgABNQAECgkJFAALAI0LAA==.Jimmypop:BAAANQADCggIFAAAAA==.',
Ju='Judadiah:BAABNQAECn8ZAAIKAAkKpw/dsQCgAQAKAAkKpw/dsQCgAQAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgIIAgAAAA==.',
['Jà']='Jàxx:BAABNQAECn8XAAIGAAgKQB08LwDnAQAGAAgKQB08LwDnAQAAAA==.',
['Jä']='Jänice:BAAANQAECggIAQAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECgkJJwAWAMUPAA==.',
Ka='Kaanha:BAAANQADCgEIAQAAAA==.Kaego:BAAANQAECgEIAQABNQAECgoKMgAlAIgWAA==.Kalinzern:BAAANQADCgEIAQAAAA==.Kalona:BAAANQADCgUICQAAAA==.Kalrock:BAABNQAECn8XAAMfAAgKBRjsiADQAQAfAAcKPBjsiADQAQARAAEK8hbKcAA+AAAAAA==.Kalrotten:BAAANQADCgcICgABNQAECggIFwAfAAUYAA==.Kalulu:BAAANQADCggIGQAAAA==.Kalyssi:BAAANQAECgQIBgAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Karkit:BAAANQADCgYIFQAAAA==.Katigotbandz:BAAANQAECgcIDQAAAA==.Katkot:BAABNQAECn8eAAITAAkKARKKlQD4AQATAAkKARKKlQD4AQAAAA==.Kayro:BAAANQADCgUICAAAAA==.Kazalandera:BAAANQADCgQICAAAAA==.Kazlan:BAAANQAECgQIBwAAAA==.Kazplan:BAAANQADCgEIAQAAAA==.Kazzulee:BAAANQADCgEIAQAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.Kepchuk:BAABNQAECn8WAAImAAgKmiVaBQBWAwAmAAgKmiVaBQBWAwAAAA==.Keres:BAACNQAFFH8PAAIDAAQKDiUJDQCDAQADAAQKDiUJDQCDAQA1AAQKfy4AAgMACgqcJI0HAIIDAAMACgqcJI0HAIIDAAAA.Keselip:BAAANQAECgYIBwAAAA==.',
Kh='Khagolith:BAABNQAECn8yAAIlAAoKiBZ3GgC7AQAlAAoKiBZ3GgC7AQAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.Kirstinn:BAAANQAECgYICAAAAA==.Kizzazz:BAAANQADCgUIBAAAAA==.',
Kk='Kkodabear:BAAANQAECgEIAgAAAA==.',
Kl='Klixeas:BAAANQAECgYIBQAAAA==.',
Kn='Knïghtshädë:BAAANQADCgUIBQAAAA==.',
Ko='Kobiter:BAABNQAECn8fAAQTAAkKahKJnADpAQATAAkKQRKJnADpAQAaAAgKjwz2egCoAQAJAAQKcxBKTwCqAAABNQAECgoKOwAPAIUhAA==.Kobito:BAABNQAECn87AAMPAAoKhSHzAgB6AwAPAAoKhSHzAgB6AwAKAAcKdBLDZwBOAQAAAA==.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECn9DAAMWAAoKoiPLBAC/AwAWAAoKoiPLBAC/AwAgAAMKMxBxOAByAAAAAA==.Koupe:BAABNQAECn8mAAMnAAkK7xnSEAAZAgAnAAgK3BrSEAAZAgAlAAUKDhCmbwAMAQABNQAECgoKQwAWAKIjAA==.',
Kr='Krang:BAAANQAECgMIBQAAAA==.Kranx:BAAANQAECgMIAwAAAA==.Krayzebeef:BAAANQAECgQIDwABNQAECgUIDgAQAAAAAA==.Kriss:BAAANQAECgUIEQAAAA==.Krystel:BAAANQADCgIIAgAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgoKQwAWAKIjAA==.Kurirne:BAAANQADCgQIBQAAAA==.',
Ky='Kyewanda:BAAANQAECggIEgAAAA==.Kyusakuu:BAAANQAECgYIDAABNQAFFAUIDAAfAC0gAA==.',
La='Laanu:BAAANQAECgIIAgABNQAECgoKNgAVAAYaAA==.Laci:BAAANQADCgYIBgAAAA==.Lagurtalokbr:BAAANQADCgIIAgAAAA==.Lahey:BAACNQAFFH8IAAIKAAQK8Ap4EwDIAAAKAAQK8Ap4EwDIAAA1AAQKfz0AAgoACgqgGVcrADECAAoACgqgGVcrADECAAAA.Lakes:BAAANQAECgYIDgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lasucia:BAAANQADCggICAAAAA==.Lathara:BAAANQAECgUIDgAAAA==.Lavs:BAABNQAECn8kAAIoAAgK1R/NBABRAgAoAAgK1R/NBABRAgAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.Layona:BAAANQADCggICAAAAA==.',
Ld='Ldykillshot:BAAANQAECgMIBAAAAA==.',
Le='Legatto:BAAANQADCgIIAgAAAA==.Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAABNQAECn8UAAITAAgKyxKQtQCzAQATAAgKyxKQtQCzAQAAAA==.Lexiah:BAABNQAECn8gAAMdAAYKhQjWgwDQAAAdAAYKhQjWgwDQAAAUAAEKAAA4kwAVAAAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lilliana:BAAANQAECgEIAQABNQAECgcIFwAOADALAA==.Linneasage:BAAANQADCgQIBAAAAA==.Lionofjudah:BAAANQABCgYIDQAAAA==.Lizardbrain:BAAANQAECgMIBwAAAQ==.',
Lo='Loamathor:BAAANQAECgYICgAAAA==.Lockkdown:BAAANQADCgYIBgAAAA==.Loesh:BAAANQADCgIJAgAAAA==.Lolyoumad:BAAANQAECggIBwAAAA==.Lorcat:BAAANQAECgEIAQAAAA==.Lorilyn:BAABNQAECn8uAAIdAAgK1R3pHgBpAgAdAAgK1R3pHgBpAgAAAA==.Lorthag:BAABNQAECn8yAAIiAAkKKxPfAgDXAQAiAAkKKxPfAgDXAQAAAA==.Lovebuz:BAAANQAECgQIBAAAAA==.Loveles:BAAANQADCggICAAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCggIDwAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Luki:BAAANQABCggIDwAAAA==.Lulbah:BAABNQAECn8UAAIeAAcK5BtuFQARAgAeAAcK5BtuFQARAgAAAA==.Lunachick:BAAANQAECgEIAQAAAA==.Lunareclips:BAAANQADCgMIBAAAAA==.Lunarus:BAABNQAECn8iAAIcAAcK2g4RCwC/AQAcAAcK2g4RCwC/AQAAAA==.',
['Lì']='Lìfe:BAABNQAECn8jAAIKAAgKZxfidgAxAgAKAAgKZxfidgAxAgAAAA==.',
['Ló']='Lónnie:BAAANQAECgMIAwAAAA==.Lónnìe:BAAANQAECgcIEAAAAA==.Lónníe:BAAANQAECgQICQAAAA==.',
Ma='Macloving:BAAANQAECgYIEAAAAA==.Maelona:BAAANQAECgcICwAAAA==.Maen:BAAANQAECgIIBAAAAA==.Magrumok:BAABNQAECn8dAAIEAAoKqBpFHQCKAQAEAAoKqBpFHQCKAQAAAA==.Magthars:BAAANQAECgMIBQAAAA==.Magtide:BAACNQAFFH8LAAIgAAQKFBmXEAAyAQAgAAQKFBmXEAAyAQA1AAQKfxQAAiAACAqMIFsYAJUCACAACAqMIFsYAJUCAAAA.Malväryx:BAABNQAECn8hAAIbAAcKHQ/7OQB1AQAbAAcKHQ/7OQB1AQAAAA==.Manbearpig:BAACNQAFFH8JAAIWAAYKzRN6DACKAQAWAAYKzRN6DACKAQA1AAQKfzIAAhYACgrDIr8KAP0CABYACgrDIr8KAP0CAAAA.Manman:BAAANQAECgMIBAAAAA==.Marqose:BAAANQADCgcIBwABNQAECgQIBgAQAAAAAA==.Marshes:BAAANQADCgIIAgABNQAECgYIDgAQAAAAAA==.Masshooter:BAAANQAECgEIAQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQAECgUIDwAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAABNQAECn8wAAIOAAoKxBs3dgCRAgAOAAoKxBs3dgCRAgAAAA==.Mellindre:BAAANQAECgQICgAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAABNQAECn8aAAIJAAgKsQygMQBTAQAJAAgKsQygMQBTAQAAAA==.Merlinsmom:BAAANQADCggICAAAAA==.Mesa:BAACNQAFFH8GAAImAAQKQhYtBwA8AQAmAAQKQhYtBwA8AQA1AAQKfwcCAyYACgrHJgwAABAEACYACgrHJgwAABAEACEAAQoaEv44AEYAAAAA.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Miclovin:BAABNQAECn8lAAMVAAkKGRipDQCbAgAVAAkKDxipDQCbAgAXAAIKBwVGlwBXAAAAAA==.Microplastic:BAABNQAECn86AAMKAAoKohp2SgCqAgAKAAoKohp2SgCqAgAPAAYK5RNdGADRAAAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAABNQAECn83AAIEAAoKyxmqDgAxAgAEAAoKyxmqDgAxAgAAAA==.Minigunn:BAAANQADCggIEAAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQAECgMIAwAAAA==.Misosmol:BAAANQAECgUICwAAAA==.Misowise:BAAANQAECgUIBgAAAA==.Missogyny:BAABNQAECn8jAAIOAAkKFyD8RAD5AgAOAAkKFyD8RAD5AgAAAA==.Mithunzi:BAAANQAECgYIDQAAAA==.',
Mo='Moadeab:BAAANQAECgEIAgAAAA==.Mogando:BAAANQAECgEIAgABNQAECgoKIQAcACwQAA==.Mogrodeath:BAAANQAECgMIBgABNQAECgoKNwAfABIfAA==.Mogrodrag:BAAANQADCggICAABNQAECgoKNwAfABIfAA==.Mogrodruid:BAAANQADCgYIBgABNQAECgoKNwAfABIfAA==.Mogrogarg:BAABNQAECn83AAQfAAoKEh8cKwDYAgAfAAoKUx0cKwDYAgARAAQKah9cCADoAAAcAAEKvB+XJABcAAAAAA==.Mogrosham:BAAANQAECgUICQABNQAECgoKNwAfABIfAA==.Mogrougarg:BAAANQAECgIIAwABNQAECgoKNwAfABIfAA==.Mojojojò:BAAANQAECgYIEAAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgoKLQApAC4aAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAFFAIIAgAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQAECgUIBQAAAA==.Moribelar:BAAANQAECgQIBgAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAABNQAECn8hAAIWAAoKyhzQEwCyAgAWAAoKyhzQEwCyAgAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAAANQAECgcIEgAAAA==.Mousyz:BAAANQAECggIBwAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAABNQAECn8xAAITAAkKGwdJ4gBXAQATAAkKGwdJ4gBXAQAAAA==.Munusku:BAAANQAECgUIDQAAAA==.Murphh:BAAANQAECggIAwAAAA==.',
My='Myboycleetus:BAAANQAECgUIDAAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.Mystie:BAAANQADCgcICwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQICAAAAA==.',
['Mï']='Mïkasa:BAAANQAECggIEAAAAA==.',
Na='Nachobussy:BAACNQAFFH8YAAMWAAcKqxYBBwDfAQAWAAYKfBgBBwDfAQAgAAYKUA95DgBWAQA1AAQKfx4AAxYACgoEJZsKAP4CABYACApgJZsKAP4CACAABQrjG9UiAOcAAAAA.Nachothings:BAABNQAECn8YAAMbAAkKlhQZJAAmAgAbAAkKlhQZJAAmAgACAAEKVhnljQBAAAABNQAFFAcIGAAWAKsWAA==.Nautico:BAAANQADCgUJBQAAAA==.',
Ne='Necrokat:BAAANQAECgQIBwAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Ner:BAAANQAECgQIBAAAAA==.Nezha:BAAANQAECggICQABNQAFFAUIDAAfAC0gAA==.',
Ni='Nicksmonk:BAAANQADCgcIBwAAAA==.Nightmist:BAAANQAECgQICAAAAA==.Nihility:BAACNQAFFH8MAAMfAAQKLSAkEgC9AAAfAAMK3yEkEgC9AAARAAEKyhxvCABZAAA1AAQKfyUAAx8ACQrRJVgHAP4CAB8ACAr4JVgHAP4CABEAAgq6IH1HAKoAAAAA.Ninobrown:BAAANQAECgEIAQAAAA==.Nirgand:BAAANQAECgEIAQABNQAECgoKIQAcACwQAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Nokoan:BAAANQAECgIIAwAAAA==.Noodlestang:BAABNQAECn8XAAMIAAcKrBA0BQA4AQAOAAYKbRKyEQFvAQAIAAYKAA80BQA4AQAAAA==.Nool:BAAANQAECgMIBAAAAA==.Norest:BAAANQADCggICAAAAA==.Norgand:BAABNQAECn8hAAMcAAoKLBASBgBTAgAcAAoK8A8SBgBTAgAfAAIKbwxDJgFzAAAAAA==.Noriboness:BAAANQAECgQIBgABNQAECgUIBQAQAAAAAA==.Nosleep:BAACNQAFFH8GAAIPAAIKywTIBABVAAAPAAIKywTIBABVAAA1AAQKfzgAAg8ACgq9FsgJAKsBAA8ACgq9FsgJAKsBAAAA.Notdumb:BAAANQAECgEIAQAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgYIBwAAAA==.Nyduss:BAABNQAECn8WAAITAAkKzx/9YQB0AgATAAkKzx/9YQB0AgAAAA==.Nyght:BAAANQADCgUIBAAAAA==.Nymphs:BAAANQADCgEIAQABNQAECggIBwAQAAAAAA==.Nyraxys:BAABNQAECn8hAAImAAkKSQvYJACaAQAmAAkKSQvYJACaAQAAAA==.Nyxira:BAAANQAECggIBgAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
['Nù']='Nùtter:BAAANQADCgMIAwAAAA==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDwAAAA==.',
Oc='Ocopoko:BAAANQAECggICQAAAA==.',
Od='Oddzmage:BAAANQAECgYICgAAAA==.',
On='Onibushi:BAABNQAECn8jAAIKAAgKghnXZABgAgAKAAgKghnXZABgAgAAAA==.',
Oo='Oof:BAAANQAECgMJAwAAAA==.Oohfookayu:BAAANQAECggIDgABNQAECgoKOQAGAPsfAA==.Oosceola:BAAANQADCgQIBQAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAABNQAECn8jAAIOAAoKcRs8VwDSAgAOAAoKcRs8VwDSAgAAAA==.',
Or='Orastal:BAABNQAECn8iAAMSAAgKHRBpDgDEAQASAAgKHRBpDgDEAQAOAAQKEgPmiwGuAAAAAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oruun:BAABNQAECn/fAAIHAAkKGSaJAgBcAwAHAAkKGSaJAgBcAwAAAA==.',
Pa='Paid:BAAANQADCgQIBAAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgQICwAAAA==.Pameliana:BAAANQAECgUICgABNQABCgYIBwAQAAAAAA==.Pandadander:BAAANQAECgYIBgABNQAECgUIDAAQAAAAAA==.Pandalo:BAAANQAECgIIAgAAAA==.Pandalock:BAABNQAECn8UAAILAAkKjQtLIAAkAQALAAkKjQtLIAAkAQAAAA==.Parasiite:BAABNQAECn8gAAIUAAoKFBVBKwDNAQAUAAoKFBVBKwDNAQAAAA==.Parasíte:BAAANQABCggICAABNQAECgoKIAAUABQVAA==.',
Pe='Peepocute:BAABNQAECn8vAAMbAAkK8BvYDwDsAQAbAAkK8BvYDwDsAQACAAYKrwrTUgBIAQAAAA==.Peghane:BAAANQADCgQIBgAAAA==.Pelarn:BAAANQADCgUIBQAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQAECgcICwAAAA==.Physiowar:BAABNQAECn8eAAIKAAkKKhYChgANAgAKAAkKKhYChgANAgAAAA==.',
Pi='Pickledeath:BAAANQAECgQIBgAAAA==.Pilik:BAAANQABCgYIBgAAAA==.Pirozhki:BAAANQADCgYIBgAAAA==.Pizzapuff:BAAANQAECgMIAwAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECn9GAAMmAAoKYiRnAgCZAwAmAAoKYiRnAgCZAwAhAAYKMR1pCACCAQAAAA==.Popavkrovi:BAAANQAFFAQIBAAAAA==.Popster:BAAANQADCgYIDQAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prada:BAAANQADCgIIAgAAAA==.Prell:BAAANQAECgQICAAAAA==.Preservation:BAAANQAECgcIEgABNQAFFAUIDAAfAC0gAA==.Primrosé:BAAANQADCgUIBQABNQAECggIFwAGAEAdAA==.Prodipriest:BAABNQAFFH8FAAIUAAMKcgnjEAC6AAAUAAMKcgnjEAC6AAAAAA==.',
Pu='Puffdragon:BAAANQADCgIIAgAAAA==.Pugi:BAAANQADCgEIAQAAAA==.Punkpally:BAAANQAECgQIBwAAAA==.Putridstrike:BAAANQAECggICQABNQAECgoKLAATAHMjAA==.',
Qt='Qtiy:BAAANQAECgUIBQABNQAECgkJMAAKAMcgAA==.Qtyy:BAABNQAECn8wAAIKAAkKxyCDGAClAgAKAAkKxyCDGAClAgAAAA==.',
Qu='Quantaboom:BAAANQADCgYIBgAAAA==.',
Ra='Raawwrr:BAAANQADCggIFAAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Raegyr:BAAANQADCggIDQAAAA==.Ragehound:BAAANQADCgYJBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ralphpalaa:BAAANQADCgEIAQAAAA==.Ramped:BAAANQAECgQICQAAAA==.Ranzor:BAABNQAECn8XAAIPAAoKMRezEAAdAgAPAAoKMRezEAAdAgAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgIIAgAAAA==.Raveyn:BAAANQAECgcIEQAAAA==.Ravn:BAAANQABCgIIAgAAAA==.Razzaa:BAAANQADCgYIBgAAAA==.',
Re='Redjak:BAAANQADCggIEAAAAA==.Regino:BAABNQAECn8hAAMTAAcKKw3gtgDsAAATAAYKFArgtgDsAAAJAAUKRQ/0RQDYAAAAAA==.Reitiado:BAAANQAECgEIAQAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECgkJGgAWAFEQAA==.Rekita:BAABNQAECn8aAAIWAAkKURD6hwD7AQAWAAkKURD6hwD7AQAAAA==.Remedi:BAAANQAECgYIEwAAAA==.Resyoself:BAAANQAECgYIBgAAAA==.Retispagheti:BAAANQADCggJCAAAAA==.Retnuh:BAABNQAECn8zAAIWAAoKpxMmPgDpAQAWAAoKpxMmPgDpAQAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQAECgIIAgAAAA==.',
Ri='Rimmjab:BAAANQAECggIEAAAAA==.Rivén:BAAANQADCggICAABNQAECggIFwAGAEAdAA==.',
Rn='Rn:BAABNQAECn8VAAIfAAoKABgWQACSAgAfAAoKABgWQACSAgAAAA==.',
Ro='Rockypalboa:BAAANQADCgcIBwAAAA==.Roderika:BAAANQAECgQIBAABNQAFFAQIDwADAA4lAA==.Roids:BAAANQADCggICgAAAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAABNQAECn8bAAIDAAgK8xdsOAAmAgADAAgK8xdsOAAmAgAAAA==.Romanflak:BAAANQAECgIIAwAAAA==.Roostr:BAABNQAECn8xAAIRAAkKEBZNAwCVAQARAAkKEBZNAwCVAQAAAA==.Rord:BAABNQAECn8qAAMTAAoKXh0kXwB7AgATAAoKXh0kXwB7AgAaAAEKvxS8GwE8AAAAAA==.Rosalei:BAAANQAECggICgAAAA==.Royjacked:BAAANQAECgMIBAAAAA==.',
Ru='Rubberr:BAAANQAECgQICQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAAANQAECgYICgAAAA==.Runicstrike:BAABNQAECn9KAAQEAAoK3CSkDABVAwAEAAkKSSOkDABVAwADAAcKxyQQDQB2AgAFAAgKfBewNABMAQABNQAECgoKLAATAHMjAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sackakt:BAAANQADCggIDQAAAA==.Sadeye:BAAANQAECggICgAAAA==.Sadie:BAAANQAECggICgABNQAECgoKLwAGAHskAA==.Sagalia:BAAANQADCgIIAgABNQAECggICAAQAAAAAA==.Sahra:BAABNQAECn8vAAIGAAoKeySZAwCwAwAGAAoKeySZAwCwAwAAAA==.Sanazale:BAABNQAECn8dAAMmAAgKIB7+DQDHAgAmAAgKIB7+DQDHAgAhAAcK1B29BAAZAgABNQAECgkJIAAhAD4gAA==.Sanctustrike:BAABNQAECn8sAAQTAAoKcyPBXwB6AgATAAoKrCHBXwB6AgAJAAcKjSDsIwDCAQAaAAMKkB2ZhAC8AAAAAA==.Sandalin:BAAANQADCgEIAQAAAA==.Saraphina:BAABNQAECn8XAAIOAAcKMAuSkAAiAQAOAAcKMAuSkAAiAQAAAA==.Saturosix:BAAANQADCgMIAwAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.Sayge:BAAANQABCgMIBAAAAA==.',
Se='Sellandre:BAABNQAECn8eAAMSAAoK1BWcCACTAQAOAAkKLBJCxwD2AQASAAcKFhScCACTAQAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECgoKIQAcACwQAA==.Seronja:BAAANQAECgQIBwAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shazzai:BAABNQAECn8ZAAIWAAkKbBhNVgCaAQAWAAkKbBhNVgCaAQAAAA==.Sherfight:BAABNQAECn8/AAMdAAoKOyRrAwDAAwAdAAoKOyRrAwDAAwAUAAQKMxopQwAbAQAAAA==.Shielddaddy:BAAANQAECggIDgAAAA==.Shieldsftl:BAABNQAECn8fAAIEAAgKcAwYMQADAQAEAAgKcAwYMQADAQABNQAECgkJFAALAI0LAA==.Shiftycent:BAAANQAECggIBQAAAA==.Shnyaga:BAACNQAFFH8GAAIdAAQKPQ0cEAAqAQAdAAQKPQ0cEAAqAQA1AAQKfxYCBB0ACgp3JskAAOkDAB0ACgp3JskAAOkDABQABAq0H4M3AGkBACIAAgpBFe4aAJEAAAAA.Shockybalboa:BAAANQAECgcIDgAAAA==.Shrider:BAAANQADCgYIEgAAAA==.Shunkd:BAAANQAECgUIBQAAAA==.Shøcker:BAAANQADCgEIAQAAAA==.',
Si='Sianda:BAAANQABCgYIBwAAAA==.Silandera:BAAANQAECgEIAgAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQABNQAECggIAwAQAAAAAA==.Sinsanityz:BAAANQAECggIDgAAAA==.Sixxsevenn:BAAANQAECgYICAAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQAECgQIBAAAAA==.',
Sk='Skinwalk:BAABNQAECn8bAAIGAAYKzRkqOAC7AQAGAAYKzRkqOAC7AQAAAA==.Skrai:BAAANQAECgQIBQAAAA==.',
Sl='Slackerftw:BAAANQAECgEIAQAAAA==.Slamhog:BAAANQAECgYIBQABNQAECgoKMAAaAPggAA==.Sleew:BAABNQAECn83AAMfAAoK8BygPgCXAgAfAAkKbxygPgCXAgARAAIKYRULTwCSAAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.Slixer:BAAANQAECgEIAQAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQADCgYIBgAAAA==.',
So='Soggypringle:BAAANQAECgEIAQAAAA==.Solary:BAAANQADCgIIAgAAAA==.Solnath:BAABNQAECn8yAAICAAoKtyOcBwCAAwACAAoKtyOcBwCAAwAAAA==.Sorcha:BAAANQADCgMIAwAAAA==.Souldaddy:BAAANQAECgUIDwAAAA==.',
Sp='Spankinstien:BAAANQAECgEIAQAAAA==.Specsdraco:BAACNQAFFH8IAAIgAAUKfQ2RFgDXAAAgAAUKfQ2RFgDXAAA1AAQKfzcAAiAACgoRI1wDAKUDACAACgoRI1wDAKUDAAAA.Spewpuke:BAABNQAECn9GAAMPAAoKwCHVAwCQAgAPAAoKwCHVAwCQAgAKAAkKzxDlhwAIAgAAAA==.Spicytomato:BAABNQAECn87AAQcAAoK1SFlAQBKAwAcAAoK1SFlAQBKAwAfAAIKdyDPzgBbAAARAAIKxxmIHQBWAAAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAABNQAECn8vAAIdAAoKNRVeKwAZAgAdAAoKNRVeKwAZAgAAAA==.Starstorm:BAAANQADCgQIBAABNQAECgoKNwAfAPAcAA==.Stgermain:BAACNQAFFH8GAAIdAAQKnRZ1EAAlAQAdAAQKnRZ1EAAlAQA1AAQKfysAAx0ACgoFHQApAMUCAB0ACgoFHQApAMUCABQABgozE8IzAIUBAAAA.Stinkybinks:BAAANQAECgUIBQAAAA==.Stormlotus:BAAANQAECgQICQAAAA==.Stormsorrow:BAABNQAECn8WAAMbAAYKngkzRwAbAQAbAAYKngkzRwAbAQABAAEKAACCOgAXAAAAAA==.Strawberry:BAEANQADCggICQABNQAECggIDgAQAAAAAA==.Strikeanywer:BAAANQAECgQICQAAAA==.',
Su='Superstoned:BAAANQADCgIJAgAAAA==.Surudk:BAAANQAECgcICgAAAA==.',
Sy='Sylrana:BAAANQAECgcIEQAAAA==.Sylri:BAAANQAECgQIBAAAAA==.Sylvie:BAAANQAECggIBgABNQAECgoKLwAGAHskAA==.',
Ta='Takticel:BAAANQAECgUICwAAAA==.Taktikal:BAAANQADCggICAABNQAECgUICwAQAAAAAA==.Taktikell:BAAANQADCgYIBgABNQAECgUICwAQAAAAAA==.Taktikil:BAAANQAECgIIAgABNQAECgUICwAQAAAAAA==.Talizar:BAAANQADCgEIAQAAAA==.Talrad:BAAANQAECggIEAAAAA==.Tauralyon:BAAANQAECggIEwABNQAECgkJHQAGAPwdAA==.Tazerxface:BAACNQAFFH8IAAIGAAQKhROPEADUAAAGAAQKhROPEADUAAA1AAQKf0gAAgYACgoGG/EUAKECAAYACgoGG/EUAKECAAAA.Tazlmao:BAAANQAECgIIAwAAAA==.',
Te='Tealgos:BAABNQAECn8eAAIhAAYKVAvPIgAyAQAhAAYKVAvPIgAyAQAAAA==.Teenyhands:BAABNQAECn8ZAAMSAAYKWwpvHQADAQASAAYKWwpvHQADAQAOAAUKEwHAqQFuAAAAAA==.Teldrasa:BAAANQAECgQIBQAAAA==.Telerein:BAAANQAECgUIBQAAAA==.Tewtz:BAAANQADCgQIBAAAAA==.',
Th='Thaiddous:BAABNQAECn8yAAIeAAoKTx5ABwATAwAeAAoKTx5ABwATAwAAAA==.Thanx:BAAANQAECgQICAAAAA==.Thealphabear:BAAANQAECgQIBgAAAA==.Thebeefchief:BAACNQAFFH8SAAIeAAUKgh7BAABXAQAeAAUKgh7BAABXAQA1AAQKfygAAh4ACgqbIzIFAEsDAB4ACgqbIzIFAEsDAAAA.Thebigmon:BAABNQAECn83AAIHAAoK/h2rGgAnAgAHAAoK/h2rGgAnAgAAAA==.Thedabara:BAAANQADCgQIBgAAAA==.Thedon:BAAANQAECgYIEwAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgcICwAAAA==.Thorxx:BAAANQAECgEIAQAAAA==.Thrudtotems:BAAANQAECggIDwAAAA==.Thrudx:BAABNQAECn8bAAMaAAoKbhb3QwBVAgAaAAoKbhb3QwBVAgATAAIKphDoaAF4AAAAAA==.Thugnastie:BAABNQAECn8jAAIHAAgKBgtSTQAlAQAHAAgKBgtSTQAlAQAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tika:BAABNQAECn8rAAISAAkKjhmtBwBzAgASAAkKjhmtBwBzAgAAAA==.Timeisdruid:BAAANQAECgQIBAAAAA==.Tinytina:BAAANQAECgcIDgAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAABNQAECn8YAAIkAAgKSBZrCgBdAQAkAAgKSBZrCgBdAQAAAA==.Togashi:BAABNQAECn8oAAILAAkKzB+/EADdAgALAAkKzB+/EADdAgAAAA==.Toof:BAAANQAECgQICQAAAA==.Topacio:BAAANQAECgQIBQAAAA==.Topnacho:BAAANQADCgEIAQABNQAFFAcIGAAWAKsWAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAABNQAECn8gAAMIAAcKlANMCACfAAAOAAcKfgO0UQEIAQAIAAUK6QFMCACfAAAAAA==.Totesschnook:BAAANQAECggIBgAAAA==.Toymueto:BAAANQAECgUICQAAAA==.',
Tr='Treespirit:BAABNQAECn8ZAAInAAkKmx3ODgDnAgAnAAkKmx3ODgDnAgAAAA==.Trenbologne:BAAANQADCgMIAwAAAA==.Trend:BAAANQAECgUIBgAAAA==.Tricep:BAAANQADCggIGAAAAA==.Tripallie:BAAANQADCgYIIwAAAA==.Trishian:BAAANQAECgEIAQAAAA==.Trunkmuffin:BAAANQAECgEIAQAAAA==.Truthless:BAECNQAFFH8KAAIaAAQKrBkeCgBEAQAaAAQKrBkeCgBEAQA1AAQKfysAAhoACgqgH1APAFEDABoACgqgH1APAFEDAAAA.',
Tu='Tuckermax:BAAANQAECgMIBQAAAA==.Tuckser:BAAANQAECgMIAwAAAA==.Tunks:BAAANQAECgYIDwAAAA==.Tusk:BAABNQAECn8dAAIGAAkK/B0bNQCLAgAGAAkK/B0bNQCLAgAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECgoKRgAmAGIkAA==.',
Ug='Uglyashell:BAAANQAECgEIAgAAAA==.',
Un='Unit:BAABNQAECn8nAAINAAkKCyPJCwC0AgANAAkKCyPJCwC0AgAAAA==.',
Uv='Uva:BAABNQAECn8XAAIjAAcKMg8mBgBLAQAjAAcKMg8mBgBLAQAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAABNQAECn8lAAIcAAkK8xGbBgBCAgAcAAkK8xGbBgBCAgAAAA==.Valsorin:BAAANQAECgQICQAAAA==.Valtaea:BAABNQAECn86AAIOAAoK/hFbPgD7AQAOAAoK/hFbPgD7AQAAAA==.',
Ve='Velanthos:BAAANQAECgEIAQAAAA==.Vershammy:BAAANQAECgEIAQAAAA==.',
Vi='Vigilus:BAAANQADCggICAAAAA==.Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQJBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgUIDgAQAAAAAA==.Voidwaffle:BAAANQADCgcIDQAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Volrog:BAAANQADCgQIBAAAAA==.Voreah:BAAANQAECgQIBQABNQAECgcIEwAQAAAAAA==.',
Wa='Waarsêer:BAAANQADCgcIBwAAAA==.Wafflxs:BAACNQAFFH8LAAIZAAYKLyH4AQAiAgAZAAYKLyH4AQAiAgA1AAQKfzEAAhkACgpmJHgDAHoDABkACgpmJHgDAHoDAAAA.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAABNQAECn8jAAITAAoKyBiedwA9AgATAAoKyBiedwA9AgAAAA==.Warglave:BAABNQAECn8aAAICAAoKQw1aIgCCAQACAAoKQw1aIgCCAQAAAA==.Warmo:BAAANQAECgMIBAAAAA==.Warunk:BAABNQAECn8UAAIgAAkKIBF2KwDvAQAgAAkKIBF2KwDvAQAAAA==.',
Wc='Wcldragon:BAAANQADCgUIBgAAAA==.',
We='Weakdog:BAAANQAECgMIAwAAAA==.Weiwu:BAACNQAFFH8TAAILAAUKRhIDCgAqAQALAAUKRhIDCgAqAQA1AAQKfzwAAgsACgqsHjMPAPACAAsACgqsHjMPAPACAAAA.Wellfookthat:BAABNQAECn85AAIGAAoK+x/fDQBSAwAGAAoK+x/fDQBSAwAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECgoKOQAGAPsfAA==.',
Wh='Whiteshadows:BAABNQAECn8jAAITAAkKxhb1dgA/AgATAAkKxhb1dgA/AgAAAA==.Whyvala:BAAANQAECgYIDAABNQADCggILgAQAAAAAA==.Whyvara:BAAANQADCggILgAAAA==.',
Wi='Wiisp:BAABNQAECn8sAAIoAAkKoR1XBwDpAQAoAAkKoR1XBwDpAQAAAA==.',
Wo='Wolneyd:BAAANQADCgIIAgABNQAECgoKTAATADgmAA==.Wolnney:BAABNQAECn9MAAITAAoKOCZxAwDhAwATAAoKOCZxAwDhAwAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
Wr='Wrath:BAAANQADCgQIBAAAAA==.',
Wu='Wubnah:BAAANQADCgIIAwAAAA==.',
['Wâ']='Wâarseer:BAAANQAECgIIAgAAAA==.',
Xa='Xairo:BAAANQAECgMIAwAAAA==.Xalatoes:BAACNQAFFH8cAAIGAAcK1B2/BQAPAgAGAAcK1B2/BQAPAgA1AAQKfy8AAgYACgquHzQeAPMCAAYACgquHzQeAPMCAAAA.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.Xandrin:BAAANQAECgMIBQAAAA==.',
Xi='Xionglieren:BAAANQADCgQIBAABNQAECgMIBwAQAAAAAA==.Xiren:BAAANQABCgQIBwAAAA==.',
Xr='Xraiz:BAABNQAECn8WAAIeAAgKog3oIAACAQAeAAgKog3oIAACAQAAAA==.',
Xy='Xyne:BAAANQADCggIEQAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAACNQAFFH8SAAIZAAUKaR4nAwDWAQAZAAUKaR4nAwDWAQA1AAQKf0QAAhkACgpfJJACAJQDABkACgpfJJACAJQDAAAA.Yourboyblue:BAAANQADCgYIHAAAAA==.Yourmaster:BAAANQAECgcIEgAAAA==.',
Yu='Yunna:BAAANQADCggICgAAAA==.',
Yv='Yverrius:BAAANQADCgMICAAAAA==.',
Za='Zanydruid:BAAANQADCgQICQAAAA==.Zanza:BAAANQAECggIEQAAAA==.Zariana:BAAANQAECgIIBAAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zemus:BAAANQADCggIEQAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.Zepbound:BAAANQABCggIFgAAAA==.Zethrak:BAAANQAECgEIAQAAAA==.',
Zh='Zhamazu:BAAANQADCgUIBwAAAA==.Zharost:BAAANQADCggIDgAAAA==.Zhayden:BAABNQAECn8WAAIVAAcKOhf0GwD2AQAVAAcKOhf0GwD2AQAAAA==.Zhy:BAAANQAECgMIAwAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.Zidenko:BAAANQAECgQIBgAAAA==.',
Zo='Zodin:BAAANQAECgIIBAABNQAECgcICwAQAAAAAA==.Zombiez:BAABNQAECn8UAAIEAAYKSAnOQQCyAAAEAAYKSAnOQQCyAAAAAA==.Zoryn:BAAANQAECgQIBgABNQADCggICAAQAAAAAA==.',
Zw='Zwerlin:BAAANQAECgEIAgAAAA==.',
['Âb']='Âbaddön:BAAANQADCgYICwAAAA==.',
['Él']='Élowen:BAAANQAECgIIAwAAAA==.',
['ßi']='ßirdmân:BAABNQAECn8sAAITAAoK4BssTACwAgATAAoK4BssTACwAgAAAA==.',
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
