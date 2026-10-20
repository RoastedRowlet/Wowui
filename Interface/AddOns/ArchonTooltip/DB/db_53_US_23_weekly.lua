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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Unknown-Unknown','Mage-Fire','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Arcane','Warrior-Protection','Warlock-Destruction','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Paladin-Holy','Warlock-Affliction','Mage-Frost','Priest-Holy','Paladin-Protection','Druid-Guardian','Warlock-Demonology','Hunter-Marksmanship','Evoker-Devastation','Priest-Discipline','Hunter-Survival','Warrior-Fury','Druid-Balance','Druid-Restoration','Druid-Feral','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaradh:BAABNQAECn8jAAMBAAoKbgghCwC2AAABAAoKbgghCwC2AAACAAEKqQOpnwAfAAAAAA==.Aaradk:BAABNQAECn8jAAMDAAkKBQ5pWACRAQADAAkKBQ5pWACRAQAEAAEKRQOx+AAfAAABNQAECgoKIwABAG4IAA==.Aarahunt:BAAANQAECgUICQABNQAECgoKIwABAG4IAA==.',
Ab='Abaddondk:BAABNQAECn8nAAIFAAgKARZ1CADQAQAFAAgKARZ1CADQAQAAAA==.Abilify:BAAANQABCgcIIAAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Aces:BAAANQAECggIEAABNQAECggIEAAGAAAAAA==.Acez:BAAANQAECggIEAAAAA==.Acidwaste:BAAANQADCggIGgAAAA==.',
Ad='Addilynn:BAAANQAECgQICQAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAABNQAECn8wAAIHAAoKyxK3AQCBAgAHAAoKyxK3AQCBAgAAAA==.',
Ae='Aelania:BAAANQAECgYIDgAAAA==.Aelunara:BAABNQAECn8fAAMEAAYKpRe/VAC/AQAEAAYKpRe/VAC/AQADAAEKAABzzgAvAAAAAA==.Aemoz:BAAANQAECgQJBAAAAA==.Aerthalis:BAAANQADCgIIAgAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgUICgAAAA==.',
Ai='Ailric:BAAANQAECgYIDAAAAA==.Ainke:BAAANQADCgYICgAAAA==.',
Al='Alarakian:BAAANQAFFAEIAQAAAA==.Alexei:BAABNQAECn8iAAMIAAgK5RVbMACUAQAIAAgK5RVbMACUAQAJAAYKsg5THQATAQAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAABNQAECn8fAAQKAAkKCA88cgDKAQAKAAgKQQ08cgDKAQALAAUKehD7qwAZAQAMAAIK3QP6MQBWAAAAAA==.Alkhan:BAABNQAECn8dAAICAAcKGgYtLgCzAAACAAcKGgYtLgCzAAABNQAECgoKMAANADYPAA==.Allymage:BAAANQADCgMIAwAAAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altoids:BAAANQAECgUIDAAAAA==.Altos:BAACNQAFFH8IAAIOAAMKNwbvBQCVAAAOAAMKNwbvBQCVAAA1AAQKfzMAAg4ACgqqEyoPADkCAA4ACgqqEyoPADkCAAAA.Altóids:BAAANQAECgQIBAABNQAECgUIDAAGAAAAAA==.Alwayshazy:BAAANQADCgUIBQAAAA==.Alyssachik:BAAANQAECgUICQAAAA==.',
Am='Amdabear:BAAANQADCgcIDAAAAA==.',
An='Anartik:BAAANQAECggIBAAAAA==.Anavar:BAAANQADCgYIDwAAAA==.Angerclaw:BAAANQAECgcIDAAAAA==.Animeow:BAAANQAFFAQIAgAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.Annasun:BAAANQADCgUIBQABNQAECggIHgAPANERAA==.',
Ap='Apoth:BAAANQAECgcICAABNQAECggIDgAGAAAAAA==.Apothe:BAAANQAECgUIBQABNQAECggIDgAGAAAAAA==.Apotheke:BAAANQAECggIDgAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQAECgEIAQAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAABNQAECn8cAAINAAgKiBTitwAUAgANAAgKiBTitwAUAgAAAA==.Arcanofrosty:BAAANQAECgUIDQAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAABNQAECn8kAAIQAAkKgBSuGADAAQAQAAkKgBSuGADAAQAAAA==.',
Au='Aurochi:BAAANQADCgMIAwAAAA==.',
Av='Avastin:BAAANQADCgcICwAAAA==.',
Aw='Awni:BAABNQAECn8rAAIRAAkKYxY2eAAuAgARAAkKYxY2eAAuAgAAAA==.',
Ax='Axell:BAAANQAECgEIAQAAAA==.',
Ba='Bacon:BAABNQAECn8yAAISAAoKSg63JAAKAgASAAoKSg63JAAKAgAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAABNQAECn8UAAINAAcKGR7CpwAyAgANAAcKGR7CpwAyAgAAAA==.Baknow:BAAANQAECgIIAwAAAA==.Bambuu:BAAANQABCggIDAAAAA==.Bangbangji:BAAANQAECgUICgABNQAECgoKOgATAKUfAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAAANQAECgUIDwAAAA==.Bartholomeow:BAAANQADCgQIBAAAAA==.Basch:BAAANQABCgYIDAAAAA==.Battlebeats:BAAANQADCgUIBQAAAA==.Bazzoo:BAAANQAECggIDQAAAA==.',
Be='Beachbabe:BAAANQADCgcIBwAAAA==.Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAABNQAECn8vAAIUAAoKQhwuAwC5AgAUAAoKQhwuAwC5AgAAAA==.Benzos:BAABNQAECn8sAAMVAAoKniN8CwAtAwAVAAkKYiN8CwAtAwAWAAgKQCGiBAC/AgAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bethezar:BAAANQAECgcICgAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAABNQAECn82AAIXAAoKXxhBDgCfAgAXAAoKXxhBDgCfAgAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgUIDgAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQAECgUICQAAAA==.',
Bl='Bluerose:BAAANQAECgQIDQAAAA==.Blurry:BAABNQAECn8eAAIPAAgK0REZDAA2AgAPAAgK0REZDAA2AgAAAA==.',
Bo='Boltsandhoes:BAAANQADCggICAABNQAECgcIEQAGAAAAAA==.Boomidk:BAAANQAECgIIAwAAAA==.Bountmage:BAAANQAECgUIDgAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brillectra:BAAANQAECgMIAQAAAA==.Brisketboy:BAAANQADCgQJBAAAAA==.Bro:BAAANQAECgUIDgAAAA==.Brokentuskz:BAAANQAECggJAQABNQAECggIJwAFAAEWAA==.Bronthos:BAAANQADCggICAAAAA==.Brothertunks:BAAANQADCgMIAwAAAA==.Brêwski:BAAANQAECgIIAQAAAA==.',
Bu='Budago:BAAANQAECgUIBQABNQAECgYIEAAGAAAAAA==.Buffbutton:BAABNQAECn8bAAINAAgKIQ1m8wCkAQANAAgKIQ1m8wCkAQABNQAECgoKNgARAMsXAA==.Buffstallion:BAAANQAECgIIBwAAAA==.Buzzie:BAAANQADCgcIDwAAAA==.',
['Bï']='Bïllï:BAABNQAECn8oAAIKAAoKtx5+GQAwAwAKAAoKtx5+GQAwAwAAAA==.',
Ca='Caerisma:BAAANQAECgcIJgAAAQ==.Cakevswaffle:BAAANQAECggIAQAAAA==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Celestino:BAAANQADCgIIAgAAAA==.Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Chainevoker:BAAANQAECgcIDAAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQAECgYIBgABNQAECgcIJgAGAAAAAQ==.Chiang:BAAANQADCggICAAAAA==.Chudmax:BAAANQADCgYIDQAAAA==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUJBgAAAA==.',
Cl='Clegen:BAAANQADCgYIBgAAAA==.Cloax:BAABNQAECn8wAAISAAoKRx7EDAAeAwASAAoKRx7EDAAeAwAAAA==.Cláp:BAABNQAFFH8GAAIOAAYKLBcxAQDrAQAOAAYKLBcxAQDrAQAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAAANQADCggIDgABNQAECgcICAAGAAAAAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Conquerlock:BAAANQAECgMIAwAAAA==.Coobibrains:BAAANQADCgUIBwAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCggIDQAAAA==.',
Cr='Craerman:BAAANQADCgYICwABNQAECgcIJgAGAAAAAQ==.Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Cryhavok:BAABNQAECn8sAAMQAAoKmBk8UACkAgAQAAoKmBk8UACkAgAYAAIKrg7CAAF5AAAAAA==.',
Cu='Cussack:BAABNQAECn8qAAIRAAoKdyDyHABEAwARAAoKdyDyHABEAwAAAA==.Cutepandaa:BAAANQADCgQIBAAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgoKOgATAKUfAA==.Daghar:BAAANQAECgIJAwAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQAECgYIEAAAAA==.Danui:BAAANQADCgQIBAAAAA==.Darkgol:BAAANQAECgYIDgABNQAECgkJIwAQAL0OAA==.Darkmagix:BAAANQABCgEIAQAAAA==.Davioon:BAAANQAECgIIBQAAAA==.Dayrb:BAAANQAECgQIBQAAAA==.',
Db='Dblade:BAAANQAFFAQIBAAAAA==.',
De='Deadlyheal:BAAANQADCgcICAABNQADCggICAAGAAAAAA==.Deadtalini:BAABNQAECn80AAMFAAoKXht6GADGAgAFAAoKZhp6GADGAgADAAcKnxsLOQAiAgAAAA==.Deah:BAAANQAECgQIDwAAAA==.Deaththroes:BAAANQAECgQIBQAAAA==.Deckerdramon:BAABNQAECn8xAAIOAAgK8h3tAgDFAQAOAAgK8h3tAgDFAQAAAA==.Demomachin:BAABNQAECn8rAAIBAAgKrxeYAwB0AQABAAgKrxeYAwB0AQAAAA==.Demonnoodle:BAAANQADCggICQABNQAECgcIFwAHAKwQAA==.Demyze:BAAANQADCggIEAAAAA==.Densetsu:BAAANQADCgcJBwAAAA==.Destroyera:BAAANQAECgUIBgAAAA==.Deucalyon:BAAANQADCggIJAAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devourme:BAAANQAECgIIAgABNQAFFAYIGAALABQcAA==.Devours:BAACNQAFFH8YAAILAAYKFBw6CwCZAQALAAYKFBw6CwCZAQA1AAQKfyIAAgsACgrtG/gvAKICAAsACgrtG/gvAKICAAAA.Devuledegg:BAAANQADCgEIAQAAAA==.',
Di='Dirtyhooves:BAAANQADCggIDwABNQAECgMIBAAGAAAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAACNQAFFH8YAAIXAAYKiSatAACOAgAXAAYKiSatAACOAgA1AAQKfzAAAhcACgrqJiIAAAEEABcACgrqJiIAAAEEAAAA.',
Do='Doesdrool:BAAANQADCgEIAQAAAA==.Dohtem:BAAANQADCgYICwABNQAECgkJIwAMAM4cAA==.Donmegah:BAAANQAECgUIDgAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Draemon:BAAANQADCgEIAQAAAA==.Dragapult:BAAANQAECgcIBwABNQAFFAQIDwADAA4lAA==.Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Dragusysmash:BAAANQAECgEIAQAAAA==.Draki:BAAANQADCgYIEAAAAA==.Drazzin:BAAANQADCgEIAQABNQAECgoKHgAZAHkPAA==.Dredtotem:BAAANQAECgQIBAAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Duggo:BAABNQAECn8kAAIaAAYKIQ6jFgBIAQAaAAYKIQ6jFgBIAQAAAA==.Dutanu:BAAANQAECgQIBgABNQAECgkJLAAQAJ0dAA==.',
Ec='Echpochmak:BAABNQAECn8YAAIbAAgKgCMTAwAbAwAbAAgKgCMTAwAbAwAAAA==.',
Ei='Eibhlean:BAABNQAECn8jAAIcAAcKjhfQDQApAQAcAAcKjhfQDQApAQABNQAECgUICQAGAAAAAA==.Eireckt:BAAANQADCgcIDAAAAA==.Eirrin:BAAANQAECggIDQAAAA==.Eivorr:BAAANQABCgQJAgAAAA==.',
El='Elariin:BAABNQAECn8aAAMLAAcKJxzSawDIAQALAAYKIxzSawDIAQAKAAQK4QooTACsAAAAAA==.Elaril:BAAANQADCgcICAAAAA==.Eleforever:BAACNQAFFH8FAAIKAAIK4BpAIQCoAAAKAAIK4BpAIQCoAAA1AAQKfzMAAgoACgq3H/4VAEUDAAoACgq3H/4VAEUDAAAA.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcICAAAAA==.Elleredreaux:BAAANQAECgcICQAAAA==.',
Em='Emongar:BAAANQAECgQIBQAAAA==.',
En='Endomorphism:BAAANQAECgIIAgABNQAFFAcIGAAdAP4gAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ev='Eveldumboone:BAAANQAECgEIAQABNQAFFAQIEQAdAAkfAA==.Evilsugar:BAAANQABCgEIAQAAAA==.Evlynia:BAAANQADCgMIAgAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAABNQAECn8lAAIeAAgKERKJgADlAQAeAAgKERKJgADlAQAAAA==.',
Fa='Fableshoot:BAAANQAECgUIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgAGAAAAAA==.Fangtang:BAAANQAECggICAAAAA==.Fantasie:BAAANQAECgEIAQABNQAECgoKNQAbABQhAA==.Fatherclutch:BAAANQADCgQICAABNQAECgcIEAAGAAAAAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAABNQAECn8tAAMUAAoKNRzeNwDDAgAUAAoKNRzeNwDDAgAfAAMK3ggjZwCPAAAAAA==.',
Fe='Felpal:BAAANQABCgMIAQABNQAECgYIHgAgAFQLAA==.Felwoof:BAABNQAECn8pAAQZAAoK0x8xDwBbAQAeAAUKTB7RmgCkAQAZAAYKgx8xDwBbAQAPAAEKWCJkYQBiAAAAAA==.Felzak:BAAANQADCgYIBgABNQAECgQIBgAGAAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgYIDwAAAA==.Fistachio:BAAANQADCgYIBgAAAA==.',
Fl='Flarllek:BAAANQADCgQICwAAAA==.Flexxed:BAABNQAECn8jAAIFAAkKhyHgFgDUAgAFAAkKhyHgFgDUAgAAAA==.',
Fo='Foopz:BAAANQADCgIJAgABNQAECgEIAQAGAAAAAA==.Forthehordde:BAAANQABCgcIDQAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Freddybones:BAAANQAECgEIAgAAAA==.Friendlytwo:BAAANQADCggICAAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgQIBgABNQAECgoKNQAbABQhAA==.Frostyxz:BAAANQADCgQIBAAAAA==.Fry:BAACNQAFFH8XAAISAAYKxBR3BQDgAQASAAYKxBR3BQDgAQA1AAQKfycAAhIACgpjHZQWAKcCABIACgpjHZQWAKcCAAAA.Fríeren:BAAANQADCgIIAgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgYIEAAAAA==.Fumblemore:BAAANQADCgEIAQAAAA==.Furystrike:BAABNQAECn8kAAMOAAkKYCNkBgAAAwAOAAkK5SJkBgAAAwARAAgKOh/GQwC+AgABNQAECgoKKgAQAKsiAA==.Futbuckmcgee:BAAANQADCgYIBgAAAA==.',
Ga='Galixie:BAAANQABCgQIBwAAAA==.Ganondrow:BAABNQAECn8sAAQSAAoKbB7pAgD9AQASAAoKbB7pAgD9AQAbAAMKqhrmtAD4AAAhAAEKng6XJgA8AAAAAA==.',
Ge='Gehagnute:BAAANQADCgEIAQAAAA==.Gemelo:BAABNQAECn8YAAIiAAoKZxDsBgAbAgAiAAoKZxDsBgAbAgAAAA==.Geromul:BAAANQADCgYIDgAAAA==.Gerrexs:BAAANQAECggIEQAAAA==.',
Gh='Ghst:BAAANQAECgcIBwAAAA==.',
Gi='Gibayy:BAABNQAECn8UAAINAAYK+yDfMABfAQANAAYK+yDfMABfAQAAAA==.Gibsonex:BAAANQAECgYIDAAAAA==.Gideone:BAAANQADCgYIBgAAAA==.Gildagni:BAAANQAECgMIAwAAAA==.Gilliamm:BAABNQAECn8yAAMTAAoKzROWIwCsAQATAAcK4BSWIwCsAQAVAAUKgBFrWgBPAQAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Go='Golath:BAABNQAECn8jAAIQAAkKvQ6znwDiAQAQAAkKvQ6znwDiAQAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAAANQAECgcIDAAAAA==.Gothbutta:BAAANQAECgQICAAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Grandena:BAAANQADCgUICgAAAA==.Graydeon:BAAANQAECgYICwAAAA==.Greatangel:BAAANQADCgUIBAABNQAECggIHgAPANERAA==.Gregano:BAAANQAECgUIBAABNQAECgkJHgARACkMAA==.Gregorian:BAABNQAECn8eAAIRAAkKKQwBqQC2AQARAAkKKQwBqQC2AQAAAA==.Gremliin:BAACNQAFFH8FAAIbAAIK6w5/FQB7AAAbAAIK6w5/FQB7AAA1AAQKfzYAAhsACQoiIHoWAB8DABsACQoiIHoWAB8DAAAA.Gremliinss:BAAANQADCgYIBgAAAA==.Gretch:BAAANQADCggICAAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Ha='Hadesdecends:BAAANQADCgMIAwAAAA==.Halakal:BAAANQAECgQIBgAAAA==.Hammerbell:BAAANQAECggJCAAAAA==.Haviboomer:BAAANQAECgQICAAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.Haywardlol:BAAANQAECggICAAAAA==.',
He='Healmeharder:BAAANQADCgEIAQAAAA==.Healminth:BAAANQAFFAQIAgAAAA==.Healthcare:BAAANQAECgIIAgAAAA==.Hethar:BAAANQAECgEIAQAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hightide:BAAANQAECgUICgAAAA==.Hippo:BAAANQAECgYIEAAAAA==.',
Ho='Hoja:BAAANQAECgEIAgAAAA==.Holdor:BAAANQADCgUIBgAAAA==.Holdors:BAAANQADCggIDAAAAA==.Holier:BAAANQADCgYIBgABNQADCggJCAAGAAAAAA==.Holybloodboi:BAAANQAECgEJAQABNQAECgkJIQALAA4iAA==.Holybuns:BAAANQADCgcIBwAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIBQABNQAECgcIFwAHAKwQAA==.',
Ht='Htilogak:BAAANQADCggICAAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAABNQAECgYIBwAGAAAAAA==.',
Ic='Iceberg:BAAANQADCgYIBgAAAA==.Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQAECgMIAwAAAA==.',
In='Insanegrippy:BAAANQAECgYICQABNQAFFAcIHAALANQdAA==.Intaria:BAABNQAECn8oAAMRAAkKaxYpdAA4AgARAAkKLhYpdAA4AgAjAAMKQxR6IgCjAAAAAA==.Invisibulity:BAAANQADCgYICQABNQAECgYIHgAgAFQLAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgIIAgAAAA==.Itsrambo:BAAANQAECgcIDwAAAA==.',
Ja='Jackbeef:BAABNQAECn8oAAIjAAoKXiAfAwAvAwAjAAoKXiAfAwAvAwAAAA==.Jadedhooves:BAABNQAECn8eAAIQAAcKiRBkggDJAAAQAAcKiRBkggDJAAAAAA==.Jaggedlilhun:BAABNQAECn8iAAIUAAkKjQ7XfQASAgAUAAkKjQ7XfQASAgAAAA==.Jaggedshammy:BAAANQAECgYIDgABNQAECgkJIgAUAI0OAA==.Jagruk:BAAANQADCgIIAgABNQAECgQIBgAGAAAAAA==.Jak:BAAANQADCgUIBQAAAA==.Jareyk:BAABNQAECn8tAAIYAAoKWBTfQgBZAgAYAAoKWBTfQgBZAgAAAA==.Jarladorin:BAAANQAECgIIAgABNQAECggIGAARAJgPAA==.Jarlu:BAAANQAECggICgAAAA==.Jaxodk:BAABNQAECn8lAAMEAAgKWSMdFgAKAwAEAAgKqiIdFgAKAwAFAAgKeh8eIQCEAgAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jecka:BAAANQAECgEIAgAAAA==.Jecynth:BAAANQADCgIIAgAAAA==.Jedai:BAACNQAFFH8IAAIYAAQKfhYxEgA9AQAYAAQKfhYxEgA9AQA1AAQKfzkAAhgACgr4HFQdAP4CABgACgr4HFQdAP4CAAAA.Jellybeann:BAAANQADCgUIDgAAAA==.Jerrysix:BAABNQAECn8jAAMSAAkKfROlKQDbAQASAAgK/hSlKQDbAQAhAAcK6RIFDQBlAQAAAA==.Jerrytwo:BAAANQAECgQIBgAAAA==.',
Ji='Jilseponie:BAAANQABCgIIBAABNQAECggIGgAEAC0LAA==.Jimmypop:BAAANQADCggIFAAAAA==.',
Ju='Judadiah:BAABNQAECn8YAAIRAAgKmA/dsQCgAQARAAgKmA/dsQCgAQAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgIIAgAAAA==.',
['Jà']='Jàxx:BAAANQAECgcIEQAAAA==.',
['Jä']='Jänice:BAAANQAECggIAQAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECgkJIgAUAI0OAA==.',
Ka='Kaanha:BAAANQADCgEIAQAAAA==.Kaego:BAAANQAECgEIAQABNQAECggILAAkAGYXAA==.Kalinzern:BAAANQADCgEIAQAAAA==.Kalona:BAAANQADCgUICQAAAA==.Kalrock:BAABNQAECn8VAAMeAAgKBRjsiADQAQAeAAcKPBjsiADQAQAPAAEK8hbKcAA+AAAAAA==.Kalrotten:BAAANQADCgcICgABNQAECggIFQAeAAUYAA==.Kalulu:BAAANQADCggIGQAAAA==.Kalyssi:BAAANQAECgQIBgAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Karkit:BAAANQADCgYIFQAAAA==.Katkot:BAABNQAECn8cAAIQAAkKARKKlQD4AQAQAAkKARKKlQD4AQAAAA==.Kayro:BAAANQADCgUICAAAAA==.Kazalandera:BAAANQADCgQICAAAAA==.Kazlan:BAAANQAECgQIBwAAAA==.Kazzulee:BAAANQADCgEIAQAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.Keres:BAACNQAFFH8PAAIDAAQKDiXgBAAXAQADAAQKDiXgBAAXAQA1AAQKfy0AAgMACgqcJI0HAIIDAAMACgqcJI0HAIIDAAAA.Keselip:BAAANQAECgYIBwAAAA==.',
Kh='Khagolith:BAABNQAECn8sAAIkAAgKZhe4DQBxAQAkAAgKZhe4DQBxAQAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.Kirstinn:BAAANQAECgQIBQAAAA==.Kizzazz:BAAANQADCgUIBAAAAA==.',
Kk='Kkodabear:BAAANQAECgEIAgAAAA==.',
Kn='Knïghtshädë:BAAANQADCgUIBQAAAA==.',
Ko='Kobiter:BAABNQAECn8fAAQQAAkKahKJnADpAQAQAAkKQRKJnADpAQAYAAgKjwz2egCoAQAcAAQKcxBKTwCqAAABNQAECgoKNAAOAIUhAA==.Kobito:BAABNQAECn80AAMOAAoKhSHzAgB6AwAOAAoKhSHzAgB6AwARAAYK7RH9vACEAQAAAA==.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECn88AAMUAAoKRiLLBAC/AwAUAAoKRiLLBAC/AwAfAAIKoA2mNgBAAAAAAA==.Koupe:BAABNQAECn8fAAMlAAkKXxWnJwDkAQAlAAgKuhWnJwDkAQAkAAUKDhCmbwAMAQABNQAECgoKPAAUAEYiAA==.',
Kr='Krang:BAAANQAECgIIBAAAAA==.Kranx:BAAANQAECgMIAwAAAA==.Krayzebeef:BAAANQAECgQIDwABNQAECgUIDgAGAAAAAA==.Kriss:BAAANQAECgQIDAAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgoKPAAUAEYiAA==.Kurirne:BAAANQADCgQIBQAAAA==.',
Ky='Kyewanda:BAAANQAECgcIEQAAAA==.Kyusakuu:BAAANQAECgYIDAABNQAFFAQICQAeAMUeAA==.',
La='Laanu:BAAANQAECgIIAgABNQAECgcIDAAGAAAAAA==.Lagurtalokbr:BAAANQADCgIIAgAAAA==.Lahey:BAABNQAECn80AAIRAAoKbxFbSgALAQARAAoKbxFbSgALAQAAAA==.Lakes:BAAANQAECgYIDgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lathara:BAAANQAECgUIDgAAAA==.Lavs:BAABNQAECn8gAAImAAgKWR/KAACAAgAmAAgKWR/KAACAAgAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.Layona:BAAANQADCggICAAAAA==.',
Ld='Ldykillshot:BAAANQAECgMIBAAAAA==.',
Le='Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAABNQAECn8UAAIQAAgKyxKQtQCzAQAQAAgKyxKQtQCzAQAAAA==.Lexiah:BAABNQAECn8cAAMbAAYKhQiOSQDqAAAbAAYKhQiOSQDqAAASAAEKAAA4kwAVAAAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lilliana:BAAANQAECgEIAQABNQAECgUIEAAGAAAAAA==.Linneasage:BAAANQADCgQIBAAAAA==.Lionofjudah:BAAANQABCgYIDQAAAA==.Lizardbrain:BAAANQAECgMIBwAAAQ==.',
Lo='Loamathor:BAAANQAECgQIBAAAAA==.Loesh:BAAANQADCgIJAgAAAA==.Lolyoumad:BAAANQADCggICAABNQAECggIJwAbAHobAA==.Lorcat:BAAANQAECgEIAQAAAA==.Lorilyn:BAABNQAECn8nAAIbAAgK1R1gBgCOAgAbAAgK1R1gBgCOAgAAAA==.Lorthag:BAABNQAECn8rAAIhAAgKZBLhAQBbAQAhAAgKZBLhAQBbAQAAAA==.Lovebuz:BAAANQAECgQIBAAAAA==.Loveles:BAAANQADCggICAAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCggIDwAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Luki:BAAANQABCggIDwAAAA==.Lulbah:BAABNQAECn8UAAIdAAcK5BtuFQARAgAdAAcK5BtuFQARAgAAAA==.Lunachick:BAAANQAECgEIAQAAAA==.Lunareclips:BAAANQADCgMIBAAAAA==.Lunarus:BAABNQAECn8gAAIZAAcK2g4RCwC/AQAZAAcK2g4RCwC/AQAAAA==.',
['Lì']='Lìfe:BAABNQAECn8jAAIRAAgKZxfidgAxAgARAAgKZxfidgAxAgAAAA==.',
['Ló']='Lónnie:BAAANQAECgMIAwAAAA==.Lónnìe:BAAANQAECgcIEAAAAA==.Lónníe:BAAANQAECgQICQAAAA==.',
Ma='Macloving:BAAANQAECgYIEAAAAA==.Maelona:BAAANQAECgcICwAAAA==.Maen:BAAANQAECgIIBAAAAA==.Magrumok:BAABNQAECn8WAAIEAAoK1hl9EQBQAQAEAAoK1hl9EQBQAQAAAA==.Magthars:BAAANQAECgMIBQAAAA==.Magtide:BAACNQAFFH8LAAIfAAQKFBmXEAAyAQAfAAQKFBmXEAAyAQA1AAQKfxQAAh8ACAqMIFsYAJUCAB8ACAqMIFsYAJUCAAAA.Malväryx:BAABNQAECn8cAAInAAcKHQ/7OQB1AQAnAAcKHQ/7OQB1AQAAAA==.Manbearpig:BAACNQAFFH8JAAIUAAYKzRN6DACKAQAUAAYKzRN6DACKAQA1AAQKfygAAhQACgq9IrMVAEUDABQACgq9IrMVAEUDAAAA.Manman:BAAANQAECgMIBAAAAA==.Marqose:BAAANQADCgcIBwABNQAECgQIBgAGAAAAAA==.Marshes:BAAANQADCgIIAgABNQAECgYIDgAGAAAAAA==.Masshooter:BAAANQAECgEIAQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQAECgUIDwAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAABNQAECn8uAAINAAgK1h03dgCRAgANAAgK1h03dgCRAgAAAA==.Mellindre:BAAANQAECgQIBgAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAABNQAECn8aAAIcAAgKsQygMQBTAQAcAAgKsQygMQBTAQAAAA==.Merlinsmom:BAAANQADCggICAAAAA==.Mesa:BAABNQAECn/LAQMoAAoKxyYMAAAQBAAoAAoKxyYMAAAQBAAgAAEKGhL+OABGAAAAAA==.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Miclovin:BAABNQAECn8lAAMTAAkKGRipDQCbAgATAAkKDxipDQCbAgAVAAIKBwVGlwBXAAAAAA==.Microplastic:BAABNQAECn82AAMRAAoKyxd2SgCqAgARAAkK3Bl2SgCqAgAOAAYK5RN7DADnAAAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAABNQAECn8uAAIEAAkKfRn7CACkAQAEAAkKfRn7CACkAQAAAA==.Minigunn:BAAANQADCggIEAAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQAECgMIAwAAAA==.Misosmol:BAAANQAECgUIBwAAAA==.Misowise:BAAANQAECgEIAQAAAA==.Missogyny:BAABNQAECn8iAAINAAgKXCL8RAD5AgANAAgKXCL8RAD5AgAAAA==.Mithunzi:BAAANQAECgYIDQAAAA==.',
Mo='Moadeab:BAAANQAECgEIAgAAAA==.Mogando:BAAANQAECgEIAgABNQAECgoKHgAZAHkPAA==.Mogrodeath:BAAANQAECgMIBQABNQAECgoKLQAeAE8cAA==.Mogrodruid:BAAANQADCgYIBgABNQAECgoKLQAeAE8cAA==.Mogrogarg:BAABNQAECn8tAAQeAAoKTxwcKwDYAgAeAAoKkBocKwDYAgAPAAQKah+hBwCmAAAZAAEKvB+XJABcAAAAAA==.Mogrosham:BAAANQAECgIIBQABNQAECgoKLQAeAE8cAA==.Mogrougarg:BAAANQAECgIIAwABNQAECgoKLQAeAE8cAA==.Mojojojò:BAAANQAECgUIBwAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgkJKgApAMsaAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAFFAIIAgAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQAECgUIBQAAAA==.Moribelar:BAAANQAECgQIBgAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAABNQAECn8YAAIUAAkKjRnHCAA5AgAUAAkKjRnHCAA5AgAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAAANQAECgcIDgAAAA==.Mousyz:BAAANQADCgIIAgAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAABNQAECn8uAAIQAAkKnwZJ4gBXAQAQAAkKnwZJ4gBXAQAAAA==.Munusku:BAAANQAECgYICwAAAA==.',
My='Myboycleetus:BAAANQAECgUIDAAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.Mystie:BAAANQADCggICwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQICAAAAA==.',
['Mï']='Mïkasa:BAAANQAECggIDgAAAA==.',
Na='Nachobussy:BAACNQAFFH8YAAMUAAcKqxYBBwDfAQAUAAYKfBgBBwDfAQAfAAYKUA95DgBWAQA1AAQKfxQAAxQABwrUHfoZALEBABQABQoQIfoZALEBAB8ABQoID41LAAcBAAAA.Nachothings:BAABNQAECn8YAAMnAAkKlhQZJAAmAgAnAAkKlhQZJAAmAgACAAEKVhnljQBAAAABNQAFFAcIGAAUAKsWAA==.Nautico:BAAANQADCgUJBQAAAA==.',
Ne='Necrokat:BAAANQAECgMIBwAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Ner:BAAANQAECgQIBAAAAA==.Nezha:BAAANQAECggICQABNQAFFAQICQAeAMUeAA==.',
Ni='Nicksmonk:BAAANQADCgcIBwAAAA==.Nightmist:BAAANQADCggISwAAAA==.Nihility:BAACNQAFFH8JAAMeAAQKxR5YCwC9AAAeAAMKVCFYCwC9AAAPAAEKpxldBgBdAAA1AAQKfx0AAx4ACQp/I2kzALsCAB4ACApRI2kzALsCAA8AAgq6IH1HAKoAAAAA.Ninobrown:BAAANQAECgEIAQAAAA==.Nirgand:BAAANQAECgEIAQABNQAECgoKHgAZAHkPAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Nokoan:BAAANQAECgIIAwAAAA==.Noodlestang:BAABNQAECn8XAAMHAAcKrBA0BQA4AQANAAYKbRKyEQFvAQAHAAYKAA80BQA4AQAAAA==.Nool:BAAANQAECgMIBAAAAA==.Norest:BAAANQADCggICAAAAA==.Norgand:BAABNQAECn8eAAMZAAoKeQ8SBgBTAgAZAAoKeg4SBgBTAgAeAAIKbwxDJgFzAAAAAA==.Noriboness:BAAANQAECgQIBgAAAA==.Nosleep:BAABNQAECn8uAAIOAAoKAxaHDgBGAgAOAAoKAxaHDgBGAgAAAA==.Notdumb:BAAANQAECgEIAQAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgUIBgAAAA==.Nyduss:BAAANQAECggIEQAAAA==.Nymphs:BAAANQADCgEIAQABNQAECggIJwAbAHobAA==.Nyraxys:BAABNQAECn8cAAIoAAkKZgpADQDzAAAoAAkKZgpADQDzAAAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
['Nù']='Nùtter:BAAANQADCgMIAwAAAA==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDwAAAA==.',
Oc='Ocopoko:BAAANQAECggICAAAAA==.',
Od='Oddzmage:BAAANQAECgYICgAAAA==.',
On='Onibushi:BAABNQAECn8jAAIRAAgKghnXZABgAgARAAgKghnXZABgAgAAAA==.Onoda:BAAANQABCgEIAgAAAA==.',
Oo='Oof:BAAANQAECgMJAwAAAA==.Oohfookayu:BAAANQAECgYIBgABNQAECgoKMwALAPsfAA==.Oosceola:BAAANQADCgIIAgAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAABNQAECn8iAAINAAkKBho8VwDSAgANAAkKBho8VwDSAgAAAA==.',
Or='Orastal:BAABNQAECn8eAAMaAAgKng9pDgDEAQAaAAgKng9pDgDEAQANAAQKEgPmiwGuAAAAAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oruun:BAABNQAECn+iAAIKAAkKKyWRAABOAwAKAAkKKyWRAABOAwAAAA==.',
Pa='Paid:BAAANQADCgQIBAAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgQICwAAAA==.Pameliana:BAAANQAECgUICgABNQABCgYIBwAGAAAAAA==.Pandadander:BAAANQAECgYIBgABNQAECgUIDAAGAAAAAA==.Pandalo:BAAANQADCgcIEAAAAA==.Pandalock:BAAANQAECgcIDgABNQAECggIGgAEAC0LAA==.Parasiite:BAABNQAECn8bAAISAAoKyA9BKwDNAQASAAoKyA9BKwDNAQAAAA==.Parasíte:BAAANQABCggICAABNQAECgoKGwASAMgPAA==.',
Pe='Peepocute:BAABNQAECn8nAAMnAAkKzRqjAgAgAgAnAAkKzRqjAgAgAgACAAYKrwrTUgBIAQAAAA==.Peghane:BAAANQADCgQIBgAAAA==.Pelarn:BAAANQADCgUIBQAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQAECgQICAAAAA==.Physiowar:BAABNQAECn8dAAIRAAgKgBcChgANAgARAAgKgBcChgANAgAAAA==.',
Pi='Pickledeath:BAAANQAECgQIBgAAAA==.Pilik:BAAANQABCgYIBgAAAA==.Pizzapuff:BAAANQAECgEIAQAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECn89AAMoAAoKYiRnAgCZAwAoAAoKYiRnAgCZAwAgAAYKMR1MAgC1AQAAAA==.Popster:BAAANQADCgYIDQAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prada:BAAANQADCgIIAgAAAA==.Prell:BAAANQAECgQIBwAAAA==.Preservation:BAAANQAECgcIEgABNQAFFAQICQAeAMUeAA==.Primrosé:BAAANQADCgUIBQABNQAECgcIEQAGAAAAAA==.Prodipriest:BAAANQAFFAIIAgAAAA==.',
Pu='Puffdragon:BAAANQADCgIIAgAAAA==.Pugi:BAAANQADCgEIAQAAAA==.Punkpally:BAAANQAECgMIAwAAAA==.Putridstrike:BAAANQAECggICQABNQAECgoKKgAQAKsiAA==.',
Qt='Qtiy:BAAANQAECgUIBQABNQAECgkJJwARAKIgAA==.Qtyy:BAABNQAECn8nAAIRAAkKoiDBAwC4AgARAAkKoiDBAwC4AgAAAA==.',
Qu='Quantaboom:BAAANQADCgYIBgAAAA==.',
Ra='Raawwrr:BAAANQADCggIFAAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Raegyr:BAAANQADCggIDQAAAA==.Ragehound:BAAANQADCgYJBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ralphpalaa:BAAANQADCgEIAQAAAA==.Ramped:BAAANQAECgQICQAAAA==.Ranzor:BAABNQAECn8WAAIOAAkKjhezEAAdAgAOAAkKjhezEAAdAgAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgIIAgAAAA==.Raveyn:BAAANQAECgcIEQAAAA==.Razzaa:BAAANQADCgYIBgAAAA==.',
Re='Redjak:BAAANQADCggIEAAAAA==.Regino:BAABNQAECn8bAAMcAAcKqQz0RQDYAAAQAAYKpAjQIAHoAAAcAAUKRQ/0RQDYAAAAAA==.Reitiado:BAAANQAECgEIAQAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECggIGAAUAHASAA==.Rekita:BAABNQAECn8YAAIUAAgKcBL6hwD7AQAUAAgKcBL6hwD7AQAAAA==.Remedi:BAAANQAECgYIEwAAAA==.Retispagheti:BAAANQADCggJCAAAAA==.Retnuh:BAABNQAECn8sAAIUAAkKExOUIQCSAQAUAAkKExOUIQCSAQAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQAECgIIAgAAAA==.',
Ri='Rimmjab:BAAANQAECgYICQAAAA==.Rivén:BAAANQADCggICAABNQAECgcIEQAGAAAAAA==.',
Rn='Rn:BAAANQAECggIEgAAAA==.',
Ro='Rockypalboa:BAAANQADCgcIBwAAAA==.Roderika:BAAANQAECgQIBAABNQAFFAQIDwADAA4lAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAABNQAECn8YAAIDAAgK8xdsOAAmAgADAAgK8xdsOAAmAgAAAA==.Romanflak:BAAANQAECgIIAwAAAA==.Roostr:BAABNQAECn8vAAIPAAkKOxXoAADAAQAPAAkKOxXoAADAAQAAAA==.Rord:BAABNQAECn8kAAMQAAkKRBskXwB7AgAQAAkKRBskXwB7AgAYAAEKvxS8GwE8AAAAAA==.Rosalei:BAAANQAECgYICAAAAA==.Royjacked:BAAANQAECgMIBAAAAA==.',
Ru='Rubberr:BAAANQAECgQICQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAAANQAECgMIBAAAAA==.Runicstrike:BAABNQAECn9BAAQEAAoKlCSkDABVAwAEAAkKSSOkDABVAwADAAcKLyRiLABmAgAFAAcK3BhZIQAfAQABNQAECgoKKgAQAKsiAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sackakt:BAAANQADCggIDQAAAA==.Sadeye:BAAANQAECgcIAgAAAA==.Sadie:BAAANQAECgYICgABNQAECgoKKwALAMkjAA==.Sagalia:BAAANQADCgIIAgABNQAECggICAAGAAAAAA==.Sahra:BAABNQAECn8rAAILAAoKySOZAwCwAwALAAoKySOZAwCwAwAAAA==.Sanazale:BAABNQAECn8VAAMoAAgKIB7+DQDHAgAoAAgKIB7+DQDHAgAgAAIKVCNtLgCqAAABNQAECggIHgAoAO0cAA==.Sanctustrike:BAABNQAECn8qAAQQAAoKqyLBXwB6AgAQAAgKaCDBXwB6AgAcAAcKjSDsIwDCAQAYAAMKkB3uTgDCAAAAAA==.Sandalin:BAAANQADCgEIAQAAAA==.Saraphina:BAAANQAECgUIEAAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.Sayge:BAAANQABCgMIBAAAAA==.',
Se='Sellandre:BAAANQAECgcIDwAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECgoKHgAZAHkPAA==.Seronja:BAAANQAECgQIBwAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shazzai:BAAANQAECgYIEQAAAA==.Sherfight:BAABNQAECn81AAMbAAoKFCFlAwAHAwAbAAoKFCFlAwAHAwASAAQKMxopQwAbAQAAAA==.Shielddaddy:BAAANQAECgMIBwAAAA==.Shieldsftl:BAABNQAECn8aAAIEAAgKLQsGIgDhAAAEAAgKLQsGIgDhAAAAAA==.Shiftycent:BAAANQAECggIBQAAAA==.Shnyaga:BAABNQAECn/SAQQbAAoKZybJAADpAwAbAAoKZybJAADpAwASAAQKtB+DNwBpAQAhAAIKQRXuGgCRAAAAAA==.Shockybalboa:BAAANQAECgQICQAAAA==.Shrider:BAAANQADCgYIEgAAAA==.Shunkd:BAAANQAECgUIBQAAAA==.Shøcker:BAAANQADCgEIAQAAAA==.',
Si='Sianda:BAAANQABCgYIBgAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQABNQAECggIAgAGAAAAAA==.Sinsanityz:BAAANQAECggIDgAAAA==.Sixxsevenn:BAAANQAECgQIBAAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQAECgQIBAAAAA==.',
Sk='Skinwalk:BAABNQAECn8VAAILAAUKDxW+MgAYAQALAAUKDxW+MgAYAQAAAA==.Skrai:BAAANQAECgQIBQAAAA==.',
Sl='Slackerftw:BAAANQAECgEIAQAAAA==.Slamhog:BAAANQADCggICAABNQAECgkJLAAYAKAhAA==.Sleew:BAABNQAECn83AAMeAAoK8BygPgCXAgAeAAkKbxygPgCXAgAPAAIKYRULTwCSAAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQADCgYIBgAAAA==.',
So='Soggypringle:BAAANQAECgEIAQAAAA==.Solary:BAAANQADCgIIAgAAAA==.Solnath:BAABNQAECn8yAAICAAoKtyO7AAAyAwACAAoKtyO7AAAyAwAAAA==.Souldaddy:BAAANQAECgUICQAAAA==.',
Sp='Spankinstien:BAAANQADCggIFgAAAA==.Specsdraco:BAACNQAFFH8IAAIfAAUKfQ2RFgDXAAAfAAUKfQ2RFgDXAAA1AAQKfzMAAh8ACgoRI1wDAKUDAB8ACgoRI1wDAKUDAAAA.Spewpuke:BAABNQAECn8+AAMOAAoK6x9gBgABAwAOAAoK6x9gBgABAwARAAgKvxJ9TQADAQAAAA==.Spicytomato:BAABNQAECn8wAAQZAAoKkiFlAQBKAwAZAAoKkiFlAQBKAwAeAAEKdyCxlABjAAAPAAEKTxfvcQA9AAAAAA==.Spirtforge:BAAANQADCgYIBgAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAABNQAECn8rAAIbAAoKNRVvCgA+AgAbAAoKNRVvCgA+AgAAAA==.Starstorm:BAAANQADCgQIBAABNQAECgoKNwAeAPAcAA==.Stgermain:BAACNQAFFH8FAAIbAAMK9RYUDgDWAAAbAAMK9RYUDgDWAAA1AAQKfygAAxsACgqmGgApAMUCABsACgqmGgApAMUCABIABgozE8IzAIUBAAAA.Stinkybinks:BAAANQAECgUIBQAAAA==.Stormlotus:BAAANQAECgQICQAAAA==.Stormsorrow:BAAANQAECgUIEAAAAA==.Strawberry:BAAANQADCgcIBwABNQAECgcICAAGAAAAAA==.Strikeanywer:BAAANQAECgQIBgAAAA==.',
Su='Superstoned:BAAANQADCgIJAgAAAA==.Surudk:BAAANQAECgUICQAAAA==.',
Sy='Sylrana:BAAANQAECgcIDwAAAA==.Sylri:BAAANQADCgcICwAAAA==.Sylvie:BAAANQAECgYIBgABNQAECgoKKwALAMkjAA==.',
Ta='Takticel:BAAANQAECgQICAAAAA==.Taktikal:BAAANQADCggICAABNQAECgQICAAGAAAAAA==.Taktikell:BAAANQADCgYIBgABNQAECgQICAAGAAAAAA==.Taktikil:BAAANQAECgIIAgABNQAECgQICAAGAAAAAA==.Talizar:BAAANQADCgEIAQAAAA==.Talrad:BAAANQAECggICwAAAA==.Tauralyon:BAAANQAECgYIDgABNQAECggIHAALABAfAA==.Tazerxface:BAACNQAFFH8HAAILAAMKxBdoDgCaAAALAAMKxBdoDgCaAAA1AAQKfz0AAgsACgqXGmEJACwCAAsACgqXGmEJACwCAAAA.Tazlmao:BAAANQAECgIIAwAAAA==.',
Te='Tealgos:BAABNQAECn8eAAIgAAYKVAvPIgAyAQAgAAYKVAvPIgAyAQAAAA==.Teenyhands:BAABNQAECn8UAAMaAAYKTApvHQADAQAaAAYKTApvHQADAQANAAUKEwHAqQFuAAAAAA==.Teldrasa:BAAANQAECgQIBQAAAA==.Telerein:BAAANQADCgUIBwABNQAECgQIBgAGAAAAAA==.Tewtz:BAAANQADCgQIBAAAAA==.',
Th='Thaiddous:BAABNQAECn8uAAIdAAoKBx5jAQCUAgAdAAoKBx5jAQCUAgAAAA==.Thanx:BAAANQAECgQICAAAAA==.Thealphabear:BAAANQAECgQIBgAAAA==.Thebeefchief:BAACNQAFFH8RAAIdAAQKCR8EAQAKAQAdAAQKCR8EAQAKAQA1AAQKfx8AAh0ACgo8IjIFAEsDAB0ACgo8IjIFAEsDAAAA.Thebigmon:BAABNQAECn8vAAIKAAkKMR4yKwDTAgAKAAkKMR4yKwDTAgAAAA==.Thedabara:BAAANQADCgQIBgAAAA==.Thedon:BAAANQAECgYIEgAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgcICwAAAA==.Thorxx:BAAANQAECgEIAQAAAA==.Thrudtotems:BAAANQAECggIDwAAAA==.Thrudx:BAABNQAECn8XAAMYAAoKbBT3QwBVAgAYAAoKbBT3QwBVAgAQAAIKphDoaAF4AAAAAA==.Thugnastie:BAABNQAECn8cAAIKAAcKVAg+RAC/AAAKAAcKVAg+RAC/AAAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tika:BAABNQAECn8jAAIaAAkKUhmtBwBzAgAaAAkKUhmtBwBzAgAAAA==.Timeisdruid:BAAANQAECgQIBAAAAA==.Tinytina:BAAANQAECgcIDAAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAAANQAECgYIEgAAAA==.Togashi:BAABNQAECn8iAAIIAAgKwyG/EADdAgAIAAgKwyG/EADdAgAAAA==.Toof:BAAANQAECgMIBQAAAA==.Topacio:BAAANQAECgMIBAAAAA==.Topnacho:BAAANQADCgEIAQABNQAFFAcIGAAUAKsWAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAABNQAECn8gAAMHAAcKlANMCACfAAAHAAUK6QFMCACfAAANAAcKfgPwpgCAAAAAAA==.Totesschnook:BAAANQAECggIBgAAAA==.Toymueto:BAAANQAECgQIBAAAAA==.',
Tr='Treespirit:BAAANQAECggIEwAAAA==.Trenbologne:BAAANQADCgMIAwAAAA==.Trend:BAAANQAECgUIBQAAAA==.Tricep:BAAANQADCggIGAAAAA==.Tripallie:BAAANQADCgcIHwAAAA==.Trishian:BAAANQAECgEIAQAAAA==.Trunkmuffin:BAAANQAECgEIAQAAAA==.Truthless:BAECNQAFFH8GAAIYAAIKdRhCHQCkAAAYAAIKdRhCHQCkAAA1AAQKfyoAAhgACgqgH1APAFEDABgACgqgH1APAFEDAAAA.',
Tu='Tuckermax:BAAANQAECgIIAgAAAA==.Tuckser:BAAANQAECgMIAwAAAA==.Tunks:BAAANQAECgYIDwAAAA==.Tusk:BAABNQAECn8cAAILAAgKEB8bNQCLAgALAAgKEB8bNQCLAgAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECgoKPQAoAGIkAA==.',
Ug='Uglyashell:BAAANQAECgEIAgAAAA==.',
Un='Unit:BAABNQAECn8mAAIMAAkKxCDJCwC0AgAMAAkKxCDJCwC0AgAAAA==.',
Uv='Uva:BAAANQAECgUIEAAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAABNQAECn8gAAIZAAkK8xGbBgBCAgAZAAkK8xGbBgBCAgAAAA==.Valsorin:BAAANQAECgUICQAAAA==.Valtaea:BAABNQAECn8wAAINAAoKNg8RqQAwAgANAAoKNg8RqQAwAgAAAA==.',
Ve='Velanthos:BAAANQAECgEIAQAAAA==.Vershammy:BAAANQAECgEIAQAAAA==.',
Vi='Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQJBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgUIDgAGAAAAAA==.Voidwaffle:BAAANQADCgcIDQAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Volrog:BAAANQADCgQIBAAAAA==.Voreah:BAAANQAECgEIAgABNQAECgYIEAAGAAAAAA==.',
Wa='Waarsêer:BAAANQADCgcIBwAAAA==.Wafflxs:BAACNQAFFH8LAAIXAAYKLyH4AQAiAgAXAAYKLyH4AQAiAgA1AAQKfygAAhcACgpmJHgDAHoDABcACgpmJHgDAHoDAAAA.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAABNQAECn8jAAIQAAoKyBiedwA9AgAQAAoKyBiedwA9AgAAAA==.Warglave:BAAANQAECggIDgAAAA==.Warmo:BAAANQAECgMIBAAAAA==.Warunk:BAAANQAFFAEIAQAAAA==.',
Wc='Wcldragon:BAAANQADCgUIBgAAAA==.',
We='Weakdog:BAAANQAECgMIAwAAAA==.Weiwu:BAACNQAFFH8SAAIIAAUKRhK2BADKAAAIAAUKRhK2BADKAAA1AAQKfzIAAggACgptHTMPAPACAAgACgptHTMPAPACAAAA.Wellfookthat:BAABNQAECn8zAAILAAoK+x/fDQBSAwALAAoK+x/fDQBSAwAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECgoKMwALAPsfAA==.',
Wh='Whiteshadows:BAABNQAECn8fAAIQAAgKiBb1dgA/AgAQAAgKiBb1dgA/AgAAAA==.Whyvala:BAAANQAECgYIDAABNQADCggIJgAGAAAAAA==.Whyvara:BAAANQADCggIJgAAAA==.',
Wi='Wiisp:BAABNQAECn8lAAImAAkKoR2EAQAUAgAmAAkKoR2EAQAUAgAAAA==.',
Wo='Wolneyd:BAAANQADCgIIAgABNQAECgoKQAAQABMmAA==.Wolnney:BAABNQAECn9AAAIQAAoKEyZxAwDhAwAQAAoKEyZxAwDhAwAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
Wr='Wrath:BAAANQADCgQIBAAAAA==.',
Wu='Wubnah:BAAANQADCgIIAwAAAA==.',
['Wâ']='Wâarseer:BAAANQADCggIEwAAAA==.',
Xa='Xairo:BAAANQADCggIDQAAAA==.Xalatoes:BAACNQAFFH8cAAILAAcK1B2/BQAPAgALAAcK1B2/BQAPAgA1AAQKfygAAgsACgquHzQeAPMCAAsACgquHzQeAPMCAAAA.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.Xandrin:BAAANQAECgMIBQAAAA==.',
Xi='Xionglieren:BAAANQADCgQIBAABNQAECgMIBAAGAAAAAA==.Xiren:BAAANQABCgQICAAAAA==.',
Xr='Xraiz:BAAANQAECgUIDgAAAA==.',
Xy='Xyne:BAAANQADCggIEQAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAACNQAFFH8SAAIXAAUKaR5YAQCPAQAXAAUKaR5YAQCPAQA1AAQKfzoAAhcACgpfJJACAJQDABcACgpfJJACAJQDAAAA.Yourboyblue:BAAANQADCgYIFgAAAA==.Yourmaster:BAAANQAECgUICwAAAA==.',
Yu='Yunna:BAAANQADCggICgAAAA==.',
Yv='Yverrius:BAAANQADCgMICAAAAA==.',
Za='Zanydruid:BAAANQADCgQICQAAAA==.Zanza:BAAANQAECggIEAAAAA==.Zariana:BAAANQAECgMIAgAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zemus:BAAANQADCggIEQAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.Zepbound:BAAANQABCggIFgAAAA==.',
Zh='Zhamazu:BAAANQADCgUIBwAAAA==.Zharost:BAAANQADCggIDgAAAA==.Zhayden:BAABNQAECn8WAAITAAcKOhf0GwD2AQATAAcKOhf0GwD2AQAAAA==.Zhy:BAAANQAECgMIAwAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.Zidenko:BAAANQAECgQIBgAAAA==.',
Zo='Zodin:BAAANQAECgMIBAABNQAECgcICwAGAAAAAA==.Zombiez:BAAANQAECgYIDwAAAA==.Zoryn:BAAANQADCggIHAABNQADCggICAAGAAAAAA==.',
Zw='Zwerlin:BAAANQAECgEIAgAAAA==.',
['Âb']='Âbaddön:BAAANQADCgYICwAAAA==.',
['Él']='Élowen:BAAANQAECgIIAwAAAA==.',
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
