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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Unknown-Unknown','Mage-Fire','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Arcane','Warrior-Protection','Warlock-Destruction','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Paladin-Holy','Warlock-Affliction','Mage-Frost','Paladin-Protection','Druid-Guardian','Warlock-Demonology','Priest-Holy','Hunter-Marksmanship','Evoker-Devastation','Priest-Discipline','Warrior-Fury','Druid-Balance','Druid-Restoration','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaradh:BAABNQAECn8fAAMBAAgKNwd2FwA0AQABAAgKNwd2FwA0AQACAAEKqQNMnQAfAAAAAA==.Aaradk:BAABNQAECn8eAAMDAAgKxA6eVwCRAQADAAgKxA6eVwCRAQAEAAEKRQPe9QAfAAABNQAECggIHwABADcHAA==.Aarahunt:BAAANQAECgUIBgABNQAECggIHwABADcHAA==.',
Ab='Abaddondk:BAABNQAECn8fAAIFAAcKohc1PgDMAQAFAAcKohc1PgDMAQABNQAECggJAQAGAAAAAA==.Abilify:BAAANQABCgcIIAAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Aces:BAAANQAECggIEAABNQAECggIEAAGAAAAAA==.Acez:BAAANQAECggIEAAAAA==.Acidwaste:BAAANQADCggIGgAAAA==.',
Ad='Addilynn:BAAANQAECgQICAAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAABNQAECn8qAAIHAAkKXRSwAQCBAgAHAAkKXRSwAQCBAgAAAA==.',
Ae='Aelania:BAAANQAECgYICAAAAA==.Aelunara:BAABNQAECn8fAAMEAAYKpRfkUwC/AQAEAAYKpRfkUwC/AQADAAEKAACHzAAvAAAAAA==.Aemoz:BAAANQAECgQJBAAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgQICAAAAA==.',
Ai='Ailric:BAAANQAECgUIDAAAAA==.Ainke:BAAANQADCgYICgAAAA==.',
Al='Alarakian:BAAANQAECggIDQAAAA==.Alexei:BAABNQAECn8cAAMIAAcKLBbJLwCUAQAIAAcKLBbJLwCUAQAJAAYKsg4FHQATAQAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAABNQAECn8fAAQKAAkKCA+ncADKAQAKAAgKQQ2ncADKAQALAAUKehBIqgAYAQAMAAIK3QNhMQBWAAAAAA==.Alkhan:BAABNQAECn8YAAICAAcKGga+VQAwAQACAAcKGga+VQAwAQABNQAECgkJLAANAEwQAA==.Allymage:BAAANQADCgMIAwAAAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altoids:BAAANQAECgUIDAAAAA==.Altos:BAACNQAFFH8IAAIOAAMKNwbHBQCVAAAOAAMKNwbHBQCVAAA1AAQKfzEAAg4ACQrUFfMOADkCAA4ACQrUFfMOADkCAAAA.Alwayshazy:BAAANQADCgUIBQAAAA==.Alyssachik:BAAANQAECgUICQAAAA==.',
Am='Amdabear:BAAANQADCgcIDAAAAA==.',
An='Anartik:BAAANQAECggIBAAAAA==.Anavar:BAAANQADCgYIDwAAAA==.Angerclaw:BAAANQAECgYIDAAAAA==.Animeow:BAAANQAFFAIIAgAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.Annaalista:BAAANQABCgQIBwAAAA==.Annasun:BAAANQADCgUIBQABNQAECggIHAAPALIRAA==.',
Ap='Apoth:BAAANQAECgcICAABNQAECggIDgAGAAAAAA==.Apothe:BAAANQAECgUIBQABNQAECggIDgAGAAAAAA==.Apotheke:BAAANQAECggIDgAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQADCgMIAwAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAABNQAECn8aAAINAAgKiBRxtQAXAgANAAgKiBRxtQAXAgAAAA==.Arcanofrosty:BAAANQAECgUIDQAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAABNQAECn8bAAIQAAgKchTYigALAgAQAAgKchTYigALAgAAAA==.',
Au='Aurochi:BAAANQADCgMIAwAAAA==.',
Av='Avastin:BAAANQADCgcICwAAAA==.',
Aw='Awni:BAABNQAECn8oAAIRAAgKIxiddgAuAgARAAgKIxiddgAuAgAAAA==.',
Ax='Axell:BAAANQAECgEIAQAAAA==.',
Ba='Bacon:BAABNQAECn8uAAISAAkK+g5bJAAKAgASAAkK+g5bJAAKAgAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAABNQAECn8UAAINAAcKGR5gpgAzAgANAAcKGR5gpgAzAgAAAA==.Baknow:BAAANQAECgIIAwAAAA==.Bambuu:BAAANQABCggIDAAAAA==.Bangbangji:BAAANQAECgUICgABNQAECgkJMwATAL0eAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAAANQAECgUIDwAAAA==.Bartholomeow:BAAANQADCgQIBAAAAA==.Basch:BAAANQABCgYIDAAAAA==.Battlebeats:BAAANQADCgUIBQAAAA==.Bazzoo:BAAANQAECggIDQAAAA==.',
Be='Beachbabe:BAAANQADCgcIBwAAAA==.Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAABNQAECn8lAAIUAAkKRRnENADLAgAUAAkKRRnENADLAgAAAA==.Benzos:BAABNQAECn8rAAMVAAkKaSRACwAtAwAVAAgKJSRACwAtAwAWAAgKQCGbBAC/AgAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bethezar:BAAANQAECgcICgAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAABNQAECn8wAAIXAAkKrRgDDgCfAgAXAAkKrRgDDgCfAgAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgUIDgAAAA==.Bigpapapump:BAAANQADCggIAQAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQAECgUICQAAAA==.',
Bl='Bluerose:BAAANQAECgQICQAAAA==.Blurry:BAABNQAECn8cAAIPAAgKshEIDAA2AgAPAAgKshEIDAA2AgAAAA==.',
Bo='Boltsandhoes:BAAANQADCggICAABNQAECgcIEQAGAAAAAA==.Boomidk:BAAANQADCgYIBgAAAA==.Bountmage:BAAANQAECgQICQAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brillectra:BAAANQAECgMIAQAAAA==.Brisketboy:BAAANQADCgQJBAAAAA==.Bro:BAAANQAECgUIDgAAAA==.Brokentuskz:BAAANQAECggJAQAAAA==.Bronthos:BAAANQADCggICAAAAA==.Brothertunks:BAAANQADCgMIAwAAAA==.Brêwski:BAAANQAECgEIAQAAAA==.',
Bu='Budago:BAAANQADCgYIBgABNQAECgQICgAGAAAAAA==.Buffbutton:BAABNQAECn8ZAAINAAcKoQwa8QClAQANAAcKoQwa8QClAQABNQAECgkJLQARANwZAA==.Buffstallion:BAAANQAECgIIBQAAAA==.Buzzie:BAAANQADCgcIDwAAAA==.',
['Bï']='Bïllï:BAABNQAECn8kAAIKAAkKViAnGQAwAwAKAAkKViAnGQAwAwAAAA==.',
Ca='Caerisma:BAAANQAECgcIIAAAAQ==.Cakevswaffle:BAAANQAECggIAQAAAA==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Celestino:BAAANQADCgIIAgAAAA==.Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Chainevoker:BAAANQAECgYICwAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQAECgUIBQABNQAECgcIIAAGAAAAAQ==.Cheesiepoof:BAAANQABCgQIBQAAAA==.Chudmax:BAAANQADCgYIDQAAAA==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUJBgAAAA==.',
Cl='Cloax:BAABNQAECn8sAAISAAkKYCCcDAAeAwASAAkKYCCcDAAeAwAAAA==.Cláp:BAABNQAFFH8GAAIOAAYKLBcmAQDsAQAOAAYKLBcmAQDsAQAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAAANQADCggIDgABNQAECgIIAgAGAAAAAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Conquerlock:BAAANQADCgcIBgAAAA==.Coobibrains:BAAANQADCgUIBwAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCggIDQAAAA==.',
Cr='Craerman:BAAANQADCgYICwABNQAECgcIIAAGAAAAAQ==.Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Cryhavok:BAABNQAECn8oAAMQAAkKwBrPTgClAgAQAAkKwBrPTgClAgAYAAIKrg6W/QB6AAAAAA==.',
Cu='Cussack:BAABNQAECn8kAAIRAAkK/CJjHABFAwARAAkK/CJjHABFAwAAAA==.Cutepandaa:BAAANQADCgQIBAAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgkJMwATAL0eAA==.Daghar:BAAANQAECgIJAwAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQAECgQICgAAAA==.Danui:BAAANQADCgQIBAAAAA==.Darkgol:BAAANQAECgYICwABNQAECggIIAAQAA0QAA==.Davioon:BAAANQAECgIIBQAAAA==.Dayrb:BAAANQAECgMIAwAAAA==.',
Db='Dblade:BAAANQAECgYIBgAAAA==.',
De='Deadlyheal:BAAANQADCgcICAABNQADCggICAAGAAAAAA==.Deadtalini:BAABNQAECn8wAAMFAAkK5h7oFwDHAgAFAAkKyh3oFwDHAgADAAcKnxtnOAAjAgAAAA==.Deah:BAAANQAECgQICwAAAA==.Deaththroes:BAAANQAECgQIBQAAAA==.Deckerdramon:BAABNQAECn8qAAIOAAgK5x1cCQC0AgAOAAgK5x1cCQC0AgAAAA==.Demomachin:BAABNQAECn8lAAIBAAgK1xQkDQDrAQABAAgK1xQkDQDrAQAAAA==.Demonnoodle:BAAANQADCggICQABNQAECgcIEgAGAAAAAA==.Demyze:BAAANQADCggIEAAAAA==.Densetsu:BAAANQADCgcJBwAAAA==.Destroyera:BAAANQAECgUIBgAAAA==.Deucalyon:BAAANQADCggIIQAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devours:BAACNQAFFH8WAAILAAUKSRn2CgCZAQALAAUKSRn2CgCZAQA1AAQKfyEAAgsACQr6HFkvAKICAAsACQr6HFkvAKICAAAA.Devuledegg:BAAANQADCgEIAQAAAA==.',
Di='Dirtyhooves:BAAANQADCggIDwAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAACNQAFFH8XAAIXAAYKqyWqAACPAgAXAAYKqyWqAACPAgA1AAQKfy0AAhcACQr8JiAAAAIEABcACQr8JiAAAAIEAAAA.',
Do='Doesdrool:BAAANQADCgEIAQAAAA==.Dohtem:BAAANQADCgYICwABNQAECgkJIwAMAM4cAA==.Donmegah:BAAANQAECgUIDgAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Draemon:BAAANQADCgEIAQAAAA==.Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Dragusysmash:BAAANQAECgEIAQAAAA==.Draki:BAAANQADCgYIEAAAAA==.Drazzin:BAAANQADCgEIAQABNQAECgkJGgAZAKAQAA==.Dredtotem:BAAANQADCggICAAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Duggo:BAABNQAECn8fAAIaAAYKIQ5qFgBIAQAaAAYKIQ5qFgBIAQAAAA==.Dutanu:BAAANQAECgQIBgABNQAECggIJgAQAAYfAA==.',
Ei='Eibhlean:BAABNQAECn8cAAIbAAYKdBpFKgCHAQAbAAYKdBpFKgCHAQABNQAECgQICQAGAAAAAA==.Eireckt:BAAANQADCgcIDAAAAA==.Eirrin:BAAANQAECggIDAAAAA==.Eivorr:BAAANQABCgQJAgAAAA==.',
El='Elariin:BAAANQAECgUIEAAAAA==.Elaril:BAAANQADCgcIBwAAAA==.Eleforever:BAACNQAFFH8FAAIKAAIK4BqdIACoAAAKAAIK4BqdIACoAAA1AAQKfy4AAgoACQqGIaIVAEUDAAoACQqGIaIVAEUDAAAA.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcIBwAAAA==.Elleredreaux:BAAANQAECgcICQAAAA==.',
Em='Emongar:BAAANQAECgQIBQAAAA==.',
En='Endomorphism:BAAANQAECgIIAgABNQAFFAcIGAAcAP4gAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ev='Eveldumboone:BAAANQAECgEIAQABNQAFFAQIDgAcAAkfAA==.Evlynia:BAAANQADCgEIAgAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAABNQAECn8lAAIdAAgKERKlfgDlAQAdAAgKERKlfgDlAQAAAA==.',
Fa='Fableshoot:BAAANQAECgQIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgAGAAAAAA==.Fangtang:BAAANQAECggICAAAAA==.Fantasie:BAAANQAECgEIAQABNQAECgkJLQAeAGogAA==.Fatherclutch:BAAANQADCgQICAABNQAECgUICQAGAAAAAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAABNQAECn8pAAMUAAkKMh68NgDEAgAUAAkKMh68NgDEAgAfAAMK3gjMZQCPAAAAAA==.',
Fe='Felpal:BAAANQABCgMIAQABNQAECgYIHgAgAFQLAA==.Felwoof:BAABNQAECn8nAAQZAAgKlyADDwBcAQAdAAUKTB5cmACkAQAZAAQK0yADDwBcAQAPAAEKWCLJYABiAAAAAA==.Felzak:BAAANQADCgYIBgABNQAECgIIAgAGAAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgYICwAAAA==.Fistachio:BAAANQADCgYIBgAAAA==.',
Fl='Flarllek:BAAANQADCgQICwAAAA==.Flexxed:BAABNQAECn8jAAIFAAkKhyFYFgDVAgAFAAkKhyFYFgDVAgAAAA==.',
Fo='Foopz:BAAANQADCgIJAgABNQAECgEIAQAGAAAAAA==.Forthehordde:BAAANQABCgcJCwAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Freddybones:BAAANQAECgEIAgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgQIBgABNQAECgkJLQAeAGogAA==.Frostyxz:BAAANQADCgQIBAAAAA==.Fry:BAACNQAFFH8WAAISAAYKxBRBBQDiAQASAAYKxBRBBQDiAQA1AAQKfyQAAhIACQrqHmAWAKcCABIACQrqHmAWAKcCAAAA.Fríeren:BAAANQADCgIIAgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgYIEAAAAA==.Fumblemore:BAAANQADCgEIAQAAAA==.Furystrike:BAABNQAECn8hAAMOAAgKISVNBgAAAwAOAAgKlCRNBgAAAwARAAgKux7DQgC+AgABNQAECgkJJQAQAKoiAA==.Futbuckmcgee:BAAANQADCgYIBgAAAA==.',
Ga='Galenaa:BAAANQADCgUIBwAAAA==.Galixie:BAAANQABCgQIBgAAAA==.Ganondrow:BAABNQAECn8mAAQSAAgKeyHrDgAAAwASAAgKeyHrDgAAAwAeAAMKqhrMsgD4AAAhAAEKng4iJgA8AAAAAA==.',
Ge='Gehagnute:BAAANQADCgEIAQAAAA==.Gemelo:BAAANQAECgcIEQAAAA==.Geromul:BAAANQADCgYICgAAAA==.Gerrexs:BAAANQAECgcIDQAAAA==.',
Gh='Ghst:BAAANQAECgcIBwAAAA==.',
Gi='Gibayy:BAAANQAECgUIEQAAAA==.Gibsonex:BAAANQAECgQIBwAAAA==.Gideone:BAAANQADCgYIBgAAAA==.Gildagni:BAAANQADCgcIDAAAAA==.Gilliamm:BAABNQAECn8wAAMTAAkKRRMqIwCtAQATAAYKOBQqIwCtAQAVAAUKgBEEWQBOAQAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Go='Golath:BAABNQAECn8gAAIQAAgKDRAZnQDjAQAQAAgKDRAZnQDjAQAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAAANQAECgMIBgAAAA==.Gothbutta:BAAANQAECgQIBQAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Grandena:BAAANQADCgUICgAAAA==.Graydeon:BAAANQAECgYICwAAAA==.Greatangel:BAAANQADCgUIBAABNQAECggIHAAPALIRAA==.Gregano:BAAANQAECgQIBAABNQAECgkJHgARACkMAA==.Gregorian:BAABNQAECn8eAAIRAAkKKQwppwC2AQARAAkKKQwppwC2AQAAAA==.Gremliin:BAABNQAECn8yAAIeAAkKIiANFgAgAwAeAAkKIiANFgAgAwAAAA==.Gremliinss:BAAANQADCgYIBgAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Ha='Hadesdecends:BAAANQADCgMIAwAAAA==.Halakal:BAAANQAECgIIAgAAAA==.Hammerbell:BAAANQAECggJCAAAAA==.Haviboomer:BAAANQAECgIIBAAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.Haywardlol:BAAANQAECggICAAAAA==.',
He='Healmeharder:BAAANQADCgEIAQAAAA==.Healminth:BAAANQAFFAIIAgAAAA==.Healthcare:BAAANQAECgIIAgAAAA==.Hethar:BAAANQAECgEIAQAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hightide:BAAANQAECgUICQAAAA==.Hilltop:BAAANQABCgEIAQAAAA==.Hippo:BAAANQAECgYIEAAAAA==.',
Ho='Hoja:BAAANQAECgEIAgAAAA==.Holdor:BAAANQADCgUIBgAAAA==.Holdors:BAAANQADCggIDAAAAA==.Holier:BAAANQADCgYIBgABNQADCggJCAAGAAAAAA==.Holybloodboi:BAAANQAECgEJAQABNQAECgkJHwALAEUhAA==.Holybuns:BAAANQADCgcIBwAAAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIBQABNQAECgcIEgAGAAAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAABNQAECgYIBwAGAAAAAA==.',
Ic='Iceberg:BAAANQADCgYIBgAAAA==.Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQAECgMIAwAAAA==.',
In='Insanegrippy:BAAANQAECgQIBQABNQAFFAYIGgALAC0dAA==.Intaria:BAABNQAECn8oAAMRAAkKaxbPcgA4AgARAAkKLhbPcgA4AgAiAAMKQxQWIgCjAAAAAA==.Invisibulity:BAAANQADCgYICQABNQAECgYIHgAgAFQLAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgIIAgAAAA==.Itsrambo:BAAANQAECgYICQAAAA==.',
Ja='Jackbeef:BAABNQAECn8lAAIiAAkK5CEcAwAvAwAiAAkK5CEcAwAvAwAAAA==.Jadedhooves:BAABNQAECn8aAAIQAAYKTg404ABUAQAQAAYKTg404ABUAQAAAA==.Jaggedlilhun:BAABNQAECn8fAAIUAAgKaw8MfAASAgAUAAgKaw8MfAASAgAAAA==.Jaggedshammy:BAAANQAECgYICwABNQAECggIHwAUAGsPAA==.Jagruk:BAAANQADCgIIAgABNQAECgIIAgAGAAAAAA==.Jak:BAAANQADCgUIBQAAAA==.Jareyk:BAABNQAECn8qAAIYAAkKhhYrQgBaAgAYAAkKhhYrQgBaAgAAAA==.Jarladorin:BAAANQAECgIIAgABNQAECgYIEgAGAAAAAA==.Jaxodk:BAABNQAECn8hAAMEAAgKWSPnFQAKAwAEAAgKqiLnFQAKAwAFAAcKrR9wIACFAgAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jecka:BAAANQAECgEIAgAAAA==.Jedai:BAACNQAFFH8FAAIYAAQKWRPKEQA9AQAYAAQKWRPKEQA9AQA1AAQKfzIAAhgACQqrHvEcAP4CABgACQqrHvEcAP4CAAAA.Jellybeann:BAAANQADCgUIDgAAAA==.Jerrysix:BAABNQAECn8fAAMSAAgK8xQ6KQDbAQASAAcKHhY6KQDbAQAhAAYKfRD8DABkAQAAAA==.Jerrytwo:BAAANQAECgQIBAAAAA==.',
Ji='Jilseponie:BAAANQABCgIIAgABNQAECgcICAAGAAAAAA==.Jimmypop:BAAANQADCggIEAAAAA==.',
Ju='Judadiah:BAAANQAECgYIEgAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgIIAgAAAA==.',
['Jà']='Jàxx:BAAANQAECgYIDwAAAA==.',
['Jä']='Jänice:BAAANQAECggIAQAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECggIHwAUAGsPAA==.',
Ka='Kaego:BAAANQAECgEIAQABNQAECggIJgAjADQVAA==.Kalona:BAAANQADCgUICQAAAA==.Kalrock:BAAANQAECgcIEgAAAA==.Kalrotten:BAAANQADCgcICgABNQAECgcIEgAGAAAAAA==.Kalulu:BAAANQADCggIGQAAAA==.Kalyssi:BAAANQAECgQIBgAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Karkit:BAAANQADCgYIFQAAAA==.Katkot:BAABNQAECn8aAAIQAAkKARJLkwD5AQAQAAkKARJLkwD5AQAAAA==.Kayro:BAAANQADCgUICAAAAA==.Kazalandera:BAAANQADCgQIBAAAAA==.Kazlan:BAAANQAECgMIAwAAAA==.Kazzulee:BAAANQADCgEIAQAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.Keres:BAACNQAFFH8LAAIDAAQKDiW2DACDAQADAAQKDiW2DACDAQA1AAQKfysAAgMACQqZJHgHAIMDAAMACQqZJHgHAIMDAAAA.Keselip:BAAANQAECgEIAQAAAA==.',
Kh='Khagolith:BAABNQAECn8mAAIjAAgKNBV1NQA7AgAjAAgKNBV1NQA7AgAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.Kizzazz:BAAANQADCgQIBAAAAA==.',
Kk='Kkodabear:BAAANQAECgEIAgAAAA==.',
Kl='Klixeas:BAAANQADCgcICQAAAA==.',
Ko='Kobiter:BAABNQAECn8dAAQQAAkKNRUjmgDqAQAQAAgKrRMjmgDqAQAYAAgKjwyNeQCpAQAbAAQKcxBYTgCqAAABNQAECgkJLQAOAEQiAA==.Kobito:BAABNQAECn8tAAMOAAkKRCLmAgB6AwAOAAkKRCLmAgB6AwARAAYK7RHJugCFAQAAAA==.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECn82AAMUAAkKDCWxBADAAwAUAAkKDCWxBADAAwAfAAEKfhKDjAAxAAAAAA==.Koupe:BAABNQAECn8eAAMkAAgKZRZEJwDjAQAkAAcK8xZEJwDjAQAjAAUKDhCTbgALAQABNQAECgkJNgAUAAwlAA==.',
Kr='Krang:BAAANQAECgIIAwAAAA==.Kranx:BAAANQADCgUIBQAAAA==.Krayzebeef:BAAANQAECgQIDwABNQAECgUIDgAGAAAAAA==.Kriss:BAAANQAECgQICAAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgkJNgAUAAwlAA==.Kurirne:BAAANQADCgQIBQAAAA==.',
Ky='Kyewanda:BAAANQAECgcIEQAAAA==.Kyusakuu:BAAANQAECgYIDAABNQAFFAIIBQAdAB0fAA==.',
La='Laanu:BAAANQAECgIIAgAAAA==.Lagurtalokbr:BAAANQADCgIIAgAAAA==.Lahey:BAABNQAECn8tAAIRAAkKRhLsfwAXAgARAAkKRhLsfwAXAgAAAA==.Lakes:BAAANQAECgYIDgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lathara:BAAANQAECgUIDgAAAA==.Lavs:BAABNQAECn8YAAIlAAcKayHCCQCiAgAlAAcKayHCCQCiAgAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.',
Le='Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAAANQAECgcIEQAAAA==.Lexiah:BAAANQAECgUIEAAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lilliana:BAAANQAECgEIAQABNQAECgQIBwAGAAAAAA==.Linneasage:BAAANQADCgQIBAAAAA==.Lizardbrain:BAAANQAECgMIBwAAAQ==.',
Lo='Loamathor:BAAANQADCggIJQAAAA==.Loesh:BAAANQADCgIJAgAAAA==.Lorcat:BAAANQAECgEIAQAAAA==.Lorilyn:BAABNQAECn8fAAIeAAcKFB4NQABnAgAeAAcKFB4NQABnAgAAAA==.Lorthag:BAABNQAECn8lAAIhAAcKVhPSCQCxAQAhAAcKVhPSCQCxAQAAAA==.Lovebuz:BAAANQADCgYIBgAAAA==.Loveles:BAAANQADCggICAAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCggIDwAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Luki:BAAANQABCggIDQAAAA==.Lulbah:BAAANQAECgYIEQAAAA==.Lunachick:BAAANQAECgEIAQAAAA==.Lunareclips:BAAANQADCgMIBAAAAA==.Lunarus:BAABNQAECn8fAAIZAAcK2g77CgC/AQAZAAcK2g77CgC/AQAAAA==.',
['Lì']='Lìfe:BAABNQAECn8gAAIRAAgK4BZqdQAyAgARAAgK4BZqdQAyAgAAAA==.',
['Ló']='Lónnie:BAAANQAECgMIAwAAAA==.Lónnìe:BAAANQAECgcIEAAAAA==.Lónníe:BAAANQAECgQICQAAAA==.',
Ma='Macloving:BAAANQAECgUIEAAAAA==.Maelona:BAAANQAECgYICgAAAA==.Maen:BAAANQAECgIIAgAAAA==.Magrumok:BAAANQAECgYIEAAAAA==.Magthars:BAAANQAECgMIBQAAAA==.Magtide:BAACNQAFFH8LAAIfAAQKFBk/EAAyAQAfAAQKFBk/EAAyAQA1AAQKfxQAAh8ACAqMIAEYAJUCAB8ACAqMIAEYAJUCAAAA.Malväryx:BAAANQAECgUIEAAAAA==.Manbearpig:BAACNQAFFH8IAAIUAAUKZBMXDACKAQAUAAUKZBMXDACKAQA1AAQKfycAAhQACQoVI04VAEYDABQACQoVI04VAEYDAAAA.Manman:BAAANQAECgMIBAAAAA==.Marqose:BAAANQADCgcIBwABNQAECgIIAgAGAAAAAA==.Marshes:BAAANQADCgIIAgABNQAECgYIDgAGAAAAAA==.Masshooter:BAAANQAECgEIAQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQAECgUIDwAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAABNQAECn8uAAINAAgK1h3ZdACUAgANAAgK1h3ZdACUAgAAAA==.Mellindre:BAAANQAECgIIAgAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAABNQAECn8aAAIbAAgKsQwaMQBTAQAbAAgKsQwaMQBTAQAAAA==.Merlinsmom:BAAANQADCggICAAAAA==.Mesa:BAABNQAECn+FAQMmAAkKgyYMAAARBAAmAAkKgyYMAAARBAAgAAEKGhJ7OABGAAAAAA==.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Miclovin:BAABNQAECn8lAAMTAAkKGRiSDQCbAgATAAkKDxiSDQCbAgAVAAIKBwUAlABXAAAAAA==.Microplastic:BAABNQAECn8tAAMRAAkK3BkrSQCrAgARAAkK3BkrSQCrAgAOAAUKaxdfJQAUAQAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAABNQAECn8mAAIEAAcKyRsyRQABAgAEAAcKyRsyRQABAgAAAA==.Minigunn:BAAANQADCggIEAAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQAECgMIAwAAAA==.Misosmol:BAAANQAECgUIBwAAAA==.Missogyny:BAABNQAECn8hAAINAAgKXCIaRAD7AgANAAgKXCIaRAD7AgAAAA==.Mithunzi:BAAANQAECgYIDQAAAA==.',
Mo='Moadeab:BAAANQAECgEIAgAAAA==.Mogando:BAAANQAECgEIAgABNQAECgkJGgAZAKAQAA==.Mogrodeath:BAAANQAECgIIAwAAAA==.Mogrodrag:BAAANQADCggICAABNQAECgkJJwAdALQcAA==.Mogrodruid:BAAANQADCgYIBgABNQAECgkJJwAdALQcAA==.Mogrogarg:BAABNQAECn8nAAQdAAkKtBwFKgDaAgAdAAkKtRoFKgDaAgAPAAQKJhq4JwA5AQAZAAEKvB82JABdAAAAAA==.Mogrosham:BAAANQAECgIIBQAAAA==.Mogrougarg:BAAANQAECgIIAgABNQAECgkJJwAdALQcAA==.Mojojojò:BAAANQAECgMIBgAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgkJKgAnAMsaAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAFFAIIAgAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQAECgUIBQAAAA==.Moribelar:BAAANQAECgQIBgAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAAANQAECgcIDgABNQAECgkJJgAkAJ4fAA==.Morventhas:BAAANQADCgIIAgAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAAANQAECgYIDgAAAA==.Mousyz:BAAANQADCgIIAgAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAABNQAECn8rAAIQAAgKKAfq3gBXAQAQAAgKKAfq3gBXAQAAAA==.Munusku:BAAANQAECgUIBgAAAA==.',
My='Myboycleetus:BAAANQAECgUIDAAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.Mystie:BAAANQADCgcIBwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQICAAAAA==.',
['Mï']='Mïkasa:BAAANQAECgcICgAAAA==.',
Na='Nachobussy:BAABNQAFFH8SAAMUAAYK4hDEBgDfAQAUAAYKOhDEBgDfAQAfAAUK8A0qDgBWAQAAAA==.Nachothings:BAABNQAECn8YAAMoAAkKlhTAIwAnAgAoAAkKlhTAIwAnAgACAAEKVhnRiwBAAAABNQAFFAYIEgAUAOIQAA==.Nautico:BAAANQADCgUJBQAAAA==.',
Ne='Necrokat:BAAANQAECgMIBwAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Ner:BAAANQAECgQIBAAAAA==.Nezha:BAAANQAECgEJAQABNQAFFAIIBQAdAB0fAA==.',
Ni='Nicksmonk:BAAANQADCgcIBwAAAA==.Nightmist:BAAANQADCggILQAAAA==.Nihility:BAACNQAFFH8FAAIdAAIKHR8cKQC5AAAdAAIKHR8cKQC5AAA1AAQKfxsAAx0ACAraI24yALwCAB0ABwqzI24yALwCAA8AAgq6IAdHAKoAAAAA.Ninobrown:BAAANQAECgEIAQAAAA==.Nirgand:BAAANQAECgEIAQABNQAECgkJGgAZAKAQAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Nokoan:BAAANQAECgIIAwAAAA==.Noodlestang:BAAANQAECgcIEgAAAA==.Nool:BAAANQAECgEIAQAAAA==.Norest:BAAANQADCggICAAAAA==.Norgand:BAABNQAECn8aAAMZAAkKoBAEBgBTAgAZAAkKfA8EBgBTAgAdAAIKbwy+IgFzAAAAAA==.Noriboness:BAAANQAECgQIBgAAAA==.Nosleep:BAABNQAECn8qAAIOAAkKlhZRDgBGAgAOAAkKlhZRDgBGAgAAAA==.Notdumb:BAAANQADCgUJDAAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgMIAwAAAA==.Nyduss:BAAANQAECgcIDgAAAA==.Nymphs:BAAANQADCgEIAQABNQAECggIJQAeAIgaAA==.Nyraxys:BAABNQAECn8VAAImAAgKGAuYJACaAQAmAAgKGAuYJACaAQAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
['Nù']='Nùtter:BAAANQADCgMIAwAAAA==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDwAAAA==.',
Oc='Ocopoko:BAAANQADCgcIBwAAAA==.',
Od='Oddzmage:BAAANQAECgYICgAAAA==.',
On='Onibushi:BAABNQAECn8hAAIRAAgKghmdYwBgAgARAAgKghmdYwBgAgAAAA==.',
Oo='Oof:BAAANQAECgMJAwAAAA==.Oohfookayu:BAAANQADCgYIBgABNQAECgkJLwALAP4hAA==.Oosceola:BAAANQADCgIIAgAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAABNQAECn8fAAINAAkKChkCVQDWAgANAAkKChkCVQDWAgAAAA==.',
Or='Orastal:BAABNQAECn8YAAMaAAgKdw5KDgDEAQAaAAgKdw5KDgDEAQANAAQKEgMKiAGvAAABNQAECgkJJgAgAF8OAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oruun:BAABNQAECn+KAAIKAAgKDybXDACAAwAKAAgKDybXDACAAwAAAA==.',
Pa='Paid:BAAANQADCgQIBAAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgQICwAAAA==.Pameliana:BAAANQAECgUIBQABNQABCgYIBwAGAAAAAA==.Pandadander:BAAANQAECgYIBgABNQAECgUIDAAGAAAAAA==.Pandalo:BAAANQADCgcIEAAAAA==.Pandalock:BAAANQAECgcICAAAAA==.Parasiite:BAAANQAECgYIDwAAAA==.Parasíte:BAAANQABCggICAABNQAECgYIDwAGAAAAAA==.',
Pe='Peepocute:BAABNQAECn8fAAMoAAgKMBzxHgBVAgAoAAgKMBzxHgBVAgACAAYKrwrSUQBIAQAAAA==.Peghane:BAAANQADCgQIBgAAAA==.Pelarn:BAAANQADCgUIBQAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQAECgQICAAAAA==.Physiowar:BAABNQAECn8cAAIRAAgKgBd+hAANAgARAAgKgBd+hAANAgAAAA==.',
Pi='Pickledeath:BAAANQAECgQIBgAAAA==.Pilik:BAAANQABCgYIBgAAAA==.Pizzapuff:BAAANQADCgYICwAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECn80AAMmAAkK7iNhAgCZAwAmAAkK7iNhAgCZAwAgAAIKMQq8MwBsAAAAAA==.Popster:BAAANQADCgYIDQAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prell:BAAANQAECgMIAwAAAA==.Preservation:BAAANQAECgcIEgABNQAFFAIIBQAdAB0fAA==.Primrosé:BAAANQADCgUIBQABNQAECgYIDwAGAAAAAA==.Prodipriest:BAAANQAFFAIIAgAAAA==.',
Pu='Puffdragon:BAAANQADCgIIAgAAAA==.Pugi:BAAANQADCgEIAQAAAA==.Putridstrike:BAAANQAECggICQABNQAECgkJJQAQAKoiAA==.',
Qt='Qtiy:BAAANQAECgUIBQABNQAECgcIHgARAIEhAA==.Qtyy:BAABNQAECn8eAAIRAAcKgSE+UACVAgARAAcKgSE+UACVAgAAAA==.',
Qu='Quantaboom:BAAANQADCgYIBgAAAA==.',
Ra='Raawwrr:BAAANQADCggIFAAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Raegyr:BAAANQADCgcICAAAAA==.Ragehound:BAAANQADCgYJBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ralphpalaa:BAAANQADCgEIAQAAAA==.Ramped:BAAANQAECgQICQAAAA==.Ranzor:BAAANQAECgcIEgAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgIIAgAAAA==.Raveyn:BAAANQAECgcIEQAAAA==.Razzaa:BAAANQADCgYIBgAAAA==.',
Re='Redjak:BAAANQADCggIEAAAAA==.Regino:BAABNQAECn8XAAMbAAYKMw4ZRQDYAAAQAAUKLAnDHAHoAAAbAAUKRQ8ZRQDYAAAAAA==.Reitiado:BAAANQAECgEIAQAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECggIGAAUAHASAA==.Rekita:BAABNQAECn8YAAIUAAgKcBL/hQD8AQAUAAgKcBL/hQD8AQAAAA==.Remedi:BAAANQAECgYIEAAAAA==.Retaxus:BAAANQABCgEJAQAAAA==.Retispagheti:BAAANQADCggJCAAAAA==.Retnuh:BAABNQAECn8lAAIUAAgKbRHqfAAQAgAUAAgKbRHqfAAQAgAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQAECgIIAgAAAA==.',
Ri='Rimmjab:BAAANQAECgYIBwAAAA==.Rivén:BAAANQADCggICAABNQAECgYIDwAGAAAAAA==.',
Rn='Rn:BAAANQAECggIEAAAAA==.',
Ro='Rockypalboa:BAAANQADCgcIBwAAAA==.Roderika:BAAANQADCgcIDgABNQAFFAQICwADAA4lAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAABNQAECn8WAAIDAAgKsRfVNwAnAgADAAgKsRfVNwAnAgAAAA==.Romanflak:BAAANQAECgIIAgAAAA==.Roostr:BAABNQAECn8nAAIPAAgKjBHECwA7AgAPAAgKjBHECwA7AgAAAA==.Rord:BAABNQAECn8hAAMQAAgK5B1HXQB9AgAQAAgK5B1HXQB9AgAYAAEKvxRrGAE8AAAAAA==.Rosalei:BAAANQAECgYIBgAAAA==.Royjacked:BAAANQAECgMIBAAAAA==.',
Ru='Rubberr:BAAANQAECgQICQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAAANQAECgIIBAAAAA==.Runicstrike:BAABNQAECn89AAQEAAkKBiWFDABUAwAEAAkKSSOFDABUAwADAAYKuyTpKwBmAgAFAAUKIBfMYwALAQABNQAECgkJJQAQAKoiAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sackakt:BAAANQADCggIDQAAAA==.Sadie:BAAANQAECgUICQABNQAECgkJIwALACklAA==.Sagalia:BAAANQADCgIIAgABNQAECggICAAGAAAAAA==.Sahra:BAABNQAECn8jAAILAAkKKSWnAwCuAwALAAkKKSWnAwCuAwAAAA==.Sanazale:BAABNQAECn8VAAMmAAgKIB7mDQDHAgAmAAgKIB7mDQDHAgAgAAIKVCMKLgCqAAABNQAECggIFgAmAJYaAA==.Sanctustrike:BAABNQAECn8lAAQQAAkKqiKyXQB7AgAQAAgKaCCyXQB7AgAbAAYKICB6IwDCAQAYAAMKHBkfywDhAAAAAA==.Sandalin:BAAANQADCgEIAQAAAA==.Saraphina:BAAANQAECgQIBwAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.Sayge:BAAANQABCgMIBAAAAA==.',
Se='Sellandre:BAAANQAECgcIDwAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECgkJGgAZAKAQAA==.Seronja:BAAANQAECgQIBwAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shazzai:BAAANQAECgYIDwAAAA==.Sherfight:BAABNQAECn8tAAMeAAkKaiCTCwBkAwAeAAkKaiCTCwBkAwASAAQKMxpuQgAbAQAAAA==.Shielddaddy:BAAANQAECgIIBgAAAA==.Shieldsftl:BAAANQAECgYIEQABNQAECgcICAAGAAAAAA==.Shiftycent:BAAANQAECggIAQAAAA==.Shnyaga:BAABNQAECn+EAQQeAAkK4yXCAADpAwAeAAkK4yXCAADpAwASAAQKtB/2NgBpAQAhAAIKQRWtGgCRAAAAAA==.Shockybalboa:BAAANQAECgQIBAAAAA==.Shrider:BAAANQADCgYIEgAAAA==.Shunkd:BAAANQAECgUIBQAAAA==.Shøcker:BAAANQADCgEIAQAAAA==.',
Si='Sianda:BAAANQABCgQIBAAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQABNQAECggIAgAGAAAAAA==.Sinsanityz:BAAANQAECggIDgAAAA==.Sixxsevenn:BAAANQAECgQIBAAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQAECgQIBAAAAA==.',
Sk='Skinwalk:BAAANQAECgUIEQAAAA==.Skrai:BAAANQAECgQIBQAAAA==.',
Sl='Slackerftw:BAAANQADCgUIBQAAAA==.Sleew:BAABNQAECn8zAAMdAAkKcRtLPQCYAgAdAAgKmhpLPQCYAgAPAAIKYRWTTgCSAAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQADCgYIBgAAAA==.',
So='Soggypringle:BAAANQAECgEIAQAAAA==.Solary:BAAANQADCgIIAgAAAA==.Solnath:BAABNQAECn8pAAICAAkKViNwBwCAAwACAAkKViNwBwCAAwAAAA==.Souldaddy:BAAANQAECgUIBgAAAA==.',
Sp='Spankinstien:BAAANQADCggIDgAAAA==.Specsdraco:BAACNQAFFH8GAAIfAAMKkg4bFgDXAAAfAAMKkg4bFgDXAAA1AAQKfy8AAh8ACQq7JEUDAKYDAB8ACQq7JEUDAKYDAAAA.Spewpuke:BAABNQAECn80AAMOAAkKrB9JBgABAwAOAAkKrB9JBgABAwARAAgKghI2hgAJAgAAAA==.Spicytomato:BAABNQAECn8qAAMZAAkK2CBjAQBKAwAZAAkK2CBjAQBKAwAPAAEKTxdYcQA9AAAAAA==.Spirtforge:BAAANQADCgYIBgAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAABNQAECn8jAAIeAAkKKxMyTgA2AgAeAAkKKxMyTgA2AgAAAA==.Starstorm:BAAANQADCgQIBAABNQAECgkJMwAdAHEbAA==.Stgermain:BAABNQAECn8kAAMeAAkKqhtOKADGAgAeAAkKqhtOKADGAgASAAYKMxM8MwCFAQAAAA==.Stinkybinks:BAAANQADCggIDQAAAA==.Stormlotus:BAAANQAECgMICQAAAA==.Stormsorrow:BAAANQAECgUIDAAAAA==.Strikeanywer:BAAANQAECgIIAgAAAA==.',
Su='Superstoned:BAAANQADCgIJAgAAAA==.Surudk:BAAANQAECgUICQAAAA==.',
Sy='Sylrana:BAAANQAECgcIDgAAAA==.Sylri:BAAANQADCgcICwAAAA==.Sylvie:BAAANQAECgUIBQABNQAECgkJIwALACklAA==.',
Ta='Takticel:BAAANQAECgQIBQAAAA==.Taktikal:BAAANQADCggICAABNQAECgQIBQAGAAAAAA==.Taktikell:BAAANQADCgYIBgABNQAECgQIBQAGAAAAAA==.Taktikil:BAAANQAECgIIAgABNQAECgQIBQAGAAAAAA==.Talizar:BAAANQADCgEIAQAAAA==.Talrad:BAAANQAECgQIBgAAAA==.Tauralyon:BAAANQAECgYICgABNQAECggIGgALABAfAA==.Tazerxface:BAACNQAFFH8FAAILAAIKExL7IACHAAALAAIKExL7IACHAAA1AAQKfzQAAgsACQpWGTwrALQCAAsACQpWGTwrALQCAAAA.Tazomfg:BAAANQADCgUIAwAAAA==.',
Te='Tealgos:BAABNQAECn8eAAIgAAYKVAuQIgAyAQAgAAYKVAuQIgAyAQAAAA==.Teenyhands:BAAANQAECgUIDQAAAA==.Teldrasa:BAAANQAECgQIBQAAAA==.Telerein:BAAANQADCgQIBAABNQAECgQIBgAGAAAAAA==.Tewtz:BAAANQADCgQIBAAAAA==.',
Th='Thaiddous:BAABNQAECn8lAAIcAAkKiB4yBwASAwAcAAkKiB4yBwASAwAAAA==.Thanx:BAAANQAECgQICAAAAA==.Thebeefchief:BAACNQAFFH8OAAIcAAQKCR9ZAgByAQAcAAQKCR9ZAgByAQA1AAQKfxwAAhwACQqaIiIFAEsDABwACQqaIiIFAEsDAAAA.Thebigmon:BAABNQAECn8sAAIKAAgKax6OKgDTAgAKAAgKax6OKgDTAgAAAA==.Thedabara:BAAANQADCgQIBgAAAA==.Thedon:BAAANQAECgYIEgAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgcICwAAAA==.Thorxx:BAAANQAECgEIAQAAAA==.Thrudtotems:BAAANQAECggIDgAAAA==.Thrudx:BAAANQAECggIEwAAAA==.Thugnastie:BAAANQAECgYIEgAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tika:BAABNQAECn8cAAIaAAgKWhiRBwBzAgAaAAgKWhiRBwBzAgAAAA==.Timeisdruid:BAAANQAECgQIBAAAAA==.Tinytina:BAAANQAECgcICQAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAAANQAECgUIDAAAAA==.Togashi:BAABNQAECn8hAAIIAAgKsSF/EADdAgAIAAgKsSF/EADdAgAAAA==.Toof:BAAANQAECgIIAgAAAA==.Topacio:BAAANQAECgMIAwAAAA==.Topnacho:BAAANQADCgEIAQABNQAFFAYIEgAUAOIQAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAABNQAECn8cAAMHAAcK+wIsCACfAAANAAcK5AKNTgEIAQAHAAUK6QEsCACfAAAAAA==.Toymueto:BAAANQAECgQIBAAAAA==.',
Tr='Treespirit:BAAANQAECggIEwAAAA==.Trenbologne:BAAANQADCgMIAwAAAA==.Tricep:BAAANQADCggIGAAAAA==.Tripallie:BAAANQADCgYIGgAAAA==.Trishian:BAAANQAECgEIAQAAAA==.Trunkmuffin:BAAANQAECgEIAQAAAA==.Truthless:BAECNQAFFH8FAAIYAAIKdRisHACkAAAYAAIKdRisHACkAAA1AAQKfykAAhgACQoRIBYPAFEDABgACQoRIBYPAFEDAAAA.',
Tu='Tuckermax:BAAANQAECgIIAgAAAA==.Tuckser:BAAANQADCgIIAgAAAA==.Tunks:BAAANQAECgYIDwAAAA==.Tusk:BAABNQAECn8aAAILAAgKEB9uNACLAgALAAgKEB9uNACLAgAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECgkJNAAmAO4jAA==.',
Ug='Uglyashell:BAAANQAECgEIAgAAAA==.',
Un='Unit:BAABNQAECn8kAAIMAAgKJSORCwC2AgAMAAgKJSORCwC2AgAAAA==.',
Uv='Uva:BAAANQAECgUICwAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAABNQAECn8aAAIZAAkK8xGJBgBCAgAZAAkK8xGJBgBCAgAAAA==.Valsorin:BAAANQAECgQICQAAAA==.Valtaea:BAABNQAECn8sAAINAAkKTBB3pgAzAgANAAkKTBB3pgAzAgAAAA==.',
Ve='Velanthos:BAAANQAECgEIAQAAAA==.Vershammy:BAAANQAECgEIAQAAAA==.',
Vi='Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQJBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgUIDgAGAAAAAA==.Voidwaffle:BAAANQADCgcIDQAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Voreah:BAAANQAECgEIAgABNQAECgQICgAGAAAAAA==.',
Wa='Waarsêer:BAAANQADCgcIBwAAAA==.Wafflxs:BAACNQAFFH8LAAIXAAYKLyHnAQAjAgAXAAYKLyHnAQAjAgA1AAQKfyUAAhcACQrNJGgDAHoDABcACQrNJGgDAHoDAAAA.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAABNQAECn8gAAIQAAgKthlpdQA+AgAQAAgKthlpdQA+AgAAAA==.Warglave:BAAANQAECgcICgAAAA==.Warmo:BAAANQAECgMIAwAAAA==.Warunk:BAAANQAECggIEwAAAA==.',
Wc='Wcldragon:BAAANQADCgUIBgAAAA==.',
We='Weiwu:BAACNQAFFH8NAAIIAAQKRhLJCQAqAQAIAAQKRhLJCQAqAQA1AAQKfy4AAggACQoLIP4OAPACAAgACQoLIP4OAPACAAAA.Wellfookthat:BAABNQAECn8vAAILAAkK/iGdDQBTAwALAAkK/iGdDQBTAwAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECgkJLwALAP4hAA==.Weolf:BAAANQABCgIIAQAAAA==.',
Wh='Whiteshadows:BAABNQAECn8eAAIQAAgKiBa3dABAAgAQAAgKiBa3dABAAgAAAA==.Whyvala:BAAANQAECgYIBgABNQADCggIHgAGAAAAAA==.Whyvara:BAAANQADCggIHgAAAA==.',
Wi='Wiisp:BAABNQAECn8eAAIlAAgKFR39CQCbAgAlAAgKFR39CQCbAgAAAA==.',
Wo='Wolneyd:BAAANQADCgIIAgABNQAECgkJNQAQAPUlAA==.Wolnney:BAABNQAECn81AAIQAAkK9SVTAwDiAwAQAAkK9SVTAwDiAwAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
Wr='Wrath:BAAANQADCgQIBAAAAA==.',
Wu='Wubnah:BAAANQADCgIIAwAAAA==.',
['Wâ']='Wâarseer:BAAANQADCgcIEgAAAA==.',
Xa='Xairo:BAAANQADCggICAAAAA==.Xalatoes:BAACNQAFFH8aAAILAAYKLR2QBQAPAgALAAYKLR2QBQAPAgA1AAQKfycAAgsACQojIcIdAPMCAAsACQojIcIdAPMCAAAA.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.Xandrin:BAAANQAECgMIBAAAAA==.',
Xi='Xionglieren:BAAANQADCgQIBAABNQAECgEIAQAGAAAAAA==.Xiren:BAAANQABCgQIBwAAAA==.',
Xr='Xraiz:BAAANQAECgQICgAAAA==.',
Xy='Xyne:BAAANQADCggIEQAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAACNQAFFH8NAAIXAAUKaR4JAwDXAQAXAAUKaR4JAwDXAQA1AAQKfzgAAhcACQp4JIICAJUDABcACQp4JIICAJUDAAAA.Yourboyblue:BAAANQADCgYIFgAAAA==.Yourmaster:BAAANQAECgUIBQAAAA==.',
Yu='Yunna:BAAANQADCgIIAgAAAA==.',
Yv='Yverrius:BAAANQADCgMICAAAAA==.',
Za='Zanydruid:BAAANQADCgQICQAAAA==.Zanza:BAAANQAECgYIDQAAAA==.Zariana:BAAANQADCgMIAwAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zearyth:BAAANQADCgcIDQAAAA==.Zemus:BAAANQADCggIEQAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.',
Zh='Zhamazu:BAAANQADCgUIBwAAAA==.Zharost:BAAANQADCggIDgAAAA==.Zhayden:BAABNQAECn8WAAITAAcKOheWGwD2AQATAAcKOheWGwD2AQAAAA==.Zhy:BAAANQAECgMIAwAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.Zidenko:BAAANQAECgQIBgAAAA==.',
Zo='Zodin:BAAANQAECgIIAgABNQAECgYICgAGAAAAAA==.Zombiez:BAAANQAECgUIDAAAAA==.Zoryn:BAAANQADCggIHAABNQADCggICAAGAAAAAA==.',
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
