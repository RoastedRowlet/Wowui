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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Unknown-Unknown','Mage-Fire','Shaman-Elemental','Shaman-Enhancement','Shaman-Restoration','Mage-Arcane','Warrior-Protection','Warrior-Arms','Priest-Shadow','Rogue-Subtlety','Hunter-BeastMastery','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','Druid-Guardian','Warlock-Demonology','Hunter-Marksmanship','Evoker-Devastation','Warlock-Destruction','Priest-Holy','Priest-Discipline','Warrior-Fury','Druid-Balance','Paladin-Protection','Druid-Restoration','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Monk-Windwalker',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaradh:BAABNQAECoEfAAMBAAgKtweqEwA/AQABAAgKtweqEwA/AQACAAEKqQM+jQAgAAAAAA==.Aaradk:BAABNQAECoEbAAMDAAgKkg1xTwCWAQADAAgKkg1xTwCWAQAEAAEKRQNz4gAfAAABNQAECggIHwABALcHAA==.Aarahunt:BAAANQAECgUIBgABNQAECggIHwABALcHAA==.',
Ab='Abaddondk:BAABNQAECoEYAAIFAAcKSxWLMgDaAQAFAAcKSxWLMgDaAQABNQAECggJAQAGAAAAAA==.Abilify:BAAANQABCgcIIAAAAA==.Abnaruk:BAAANQAECgEIAQAAAA==.',
Ac='Aces:BAAANQAECggICAAAAA==.Acez:BAAANQAECggJEAAAAA==.Acidwaste:BAAANQADCggIFgAAAA==.',
Ad='Addilynn:BAAANQAECgQIBAAAAA==.Adoriah:BAAANQADCgYICwAAAA==.Adsaw:BAABNQAECoEhAAIHAAgKORTtAQA3AgAHAAgKORTtAQA3AgAAAA==.',
Ae='Aelania:BAAANQAECgMJAwAAAA==.Aelunara:BAABNQAECoEfAAMEAAYKTxrPSQDIAQAEAAYKTxrPSQDIAQADAAEKbxAMvgAvAAAAAA==.Aemoz:BAAANQAECgQJBAAAAA==.',
Af='Aftershocks:BAAANQAECgEIAQAAAA==.',
Ag='Agh:BAAANQAECgQIBAAAAA==.',
Ai='Ailric:BAAANQAECgUICwAAAA==.Ainke:BAAANQADCgYICgAAAA==.',
Al='Alarakian:BAAANQAECgYICAAAAA==.Alexei:BAAANQAECgUIEQAAAA==.Aliakin:BAAANQAECgMIBAAAAA==.Alistarburns:BAABNQAECoEbAAQIAAgKIg7WXwDSAQAIAAgKIg7WXwDSAQAJAAIKkgPQKwBbAAAKAAIKHAuK8QBVAAAAAA==.Alkhan:BAAANQAECgYIEwABNQAECgkJIwALAFIPAA==.Allymage:BAAANQADCgMIAwAAAA==.Alteredbeest:BAAANQADCgQIBAAAAA==.Altoids:BAAANQAECgUIBwAAAA==.Altos:BAABNQAECoErAAIMAAkK7hAyEAD4AQAMAAkK7hAyEAD4AQAAAA==.Alwayshazy:BAAANQADCgUIBQAAAA==.Alyssachik:BAAANQAECgQIBAAAAA==.',
Am='Amdabear:BAAANQADCgcIDAAAAA==.',
An='Anavar:BAAANQADCgYIDwAAAA==.Angerclaw:BAAANQAECgUICwAAAA==.Animeow:BAAANQAFFAIIAgAAAA==.Ankaramessi:BAAANQADCgQIBQAAAA==.Annaalista:BAAANQABCgQIBwAAAA==.Annasun:BAAANQADCgUIBQABNQAECgYIEQAGAAAAAA==.',
Ap='Apoth:BAAANQAECgcICAABNQAECggIDQAGAAAAAA==.Apothe:BAAANQAECgUIBQABNQAECggIDQAGAAAAAA==.Apotheke:BAAANQAECggIDQAAAA==.',
Aq='Aquaria:BAAANQADCggICAAAAA==.',
Ar='Arakisa:BAAANQADCgMIAwAAAA==.Arcanemagik:BAAANQADCggIFAAAAA==.Arcanmage:BAAANQAECgYIEAAAAA==.Arcanofrosty:BAAANQAECgUIDAAAAA==.Aresascends:BAAANQADCgUIBQAAAA==.Arinthe:BAAANQADCgQIBAAAAA==.',
At='Atalmon:BAAANQAECgYIEAAAAA==.',
Au='Aurochi:BAAANQADCgMIAwAAAA==.',
Av='Avastin:BAAANQADCgcICwAAAA==.',
Aw='Awni:BAABNQAECoEhAAINAAgKAhV7cwAZAgANAAgKAhV7cwAZAgAAAA==.',
Ba='Bacon:BAABNQAECoEnAAIOAAkKkw+MHwAZAgAOAAkKkw+MHwAZAgAAAA==.Badonkadonkk:BAAANQABCgIIAgAAAA==.Bahbahr:BAABNQAECoEUAAILAAcKWh5sjgBHAgALAAcKWh5sjgBHAgAAAA==.Baknow:BAAANQAECgIIAgAAAA==.Bambuu:BAAANQABCggIDAAAAA==.Bangbangji:BAAANQAECgUICgABNQAECgkJLQAPAFgcAA==.Bantum:BAAANQADCggICAAAAA==.Bartholas:BAABNQAECoESAAILAAYKWBKB6gCOAQALAAYKWBKB6gCOAQAAAA==.Bartholomeow:BAAANQADCgQIBAAAAA==.Basch:BAAANQABCgYIDAAAAA==.Battlebeats:BAAANQADCgUIBQAAAA==.Bazzoo:BAAANQAECgcICgAAAA==.',
Be='Beastmodex:BAAANQAECgUIBgAAAA==.Beastyboo:BAABNQAECoEfAAIQAAkK5RgZMAC6AgAQAAkK5RgZMAC6AgAAAA==.Benzos:BAABNQAECoErAAMRAAkKuyTnBwBBAwARAAgKPyTnBwBBAwASAAgKZiLEAwDOAgAAAA==.Bequin:BAAANQAECgEIAQAAAA==.Berrd:BAAANQAECgMIBAAAAA==.Bethezar:BAAANQAECgMIAwAAAA==.Bewbbs:BAAANQAECgMIAwAAAA==.',
Bh='Bhangbhang:BAABNQAECoEnAAITAAgKaRQ9FgDpAQATAAgKaRQ9FgDpAQAAAA==.',
Bi='Biggerbits:BAAANQAECgEIAQAAAA==.Bigkrayze:BAAANQAECgUIDgAAAA==.Bigpapapump:BAAANQADCggIAQAAAA==.Bigpullz:BAAANQABCgEIAQAAAA==.',
Bj='Bjordom:BAAANQAECgQIBQAAAA==.',
Bl='Bluerose:BAAANQAECgQIBQAAAA==.Blurry:BAAANQAECgYIEQAAAA==.',
Bo='Boltsandhoes:BAAANQADCggICAABNQAECgYIEAAGAAAAAA==.Bountmage:BAAANQAECgQIBQAAAA==.',
Br='Bradyswife:BAAANQADCgYIDQAAAA==.Brillectra:BAAANQAECgMIAQAAAA==.Brisketboy:BAAANQADCgQJBAAAAA==.Bro:BAAANQAECgUIDgAAAA==.Brokentuskz:BAAANQAECggJAQAAAA==.Bronthos:BAAANQADCggICAAAAA==.Brothertunks:BAAANQADCgMIAwAAAA==.Brêwski:BAAANQAECgEIAQAAAA==.',
Bu='Buffbutton:BAAANQAECgUIDgABNQAECgkJJQANAPMZAA==.Buffstallion:BAAANQAECgEIAwAAAA==.Buzzie:BAAANQADCgYICQAAAA==.',
['Bï']='Bïllï:BAABNQAECoEgAAIIAAkKHCArGgAVAwAIAAkKHCArGgAVAwAAAA==.',
Ca='Caerisma:BAAANQAECgcIFQAAAQ==.Cakevswaffle:BAAANQAECggIAQAAAA==.Caravaggio:BAAANQADCgQIBQAAAA==.Catawba:BAAANQADCgMIAwAAAA==.',
Ce='Cellica:BAAANQAECgQIBQAAAA==.Cerywen:BAAANQADCgIIAgAAAA==.',
Ch='Chadwik:BAAANQADCgYIDQAAAA==.Chainevoker:BAAANQAECgUIBQAAAA==.Charbzenberg:BAAANQAECgIIAgAAAA==.Charisma:BAAANQAECgUIBQABNQAECgcIFQAGAAAAAQ==.Cheesiepoof:BAAANQABCgQIBQAAAA==.Chudmax:BAAANQADCgYIDAAAAA==.Chungae:BAAANQABCgEIAQAAAA==.',
Ci='Ciomara:BAAANQADCgUJBgAAAA==.',
Cl='Cloax:BAABNQAECoEmAAIOAAkKqh67DQD6AgAOAAkKqh67DQD6AgAAAA==.',
Co='Cobblepot:BAAANQABCgUIBQAAAA==.Coconut:BAAANQADCgQIBgABNQAECgEIAQAGAAAAAA==.Coinbrew:BAAANQADCgQIBAAAAA==.Comardrac:BAAANQADCgQIBAAAAA==.Coned:BAAANQADCgEIAQAAAA==.Conquerwar:BAAANQADCgcIBgAAAA==.Coobibrains:BAAANQADCgUIBwAAAA==.Coobin:BAAANQADCgQIBAAAAA==.Coobins:BAAANQADCggIDQAAAA==.',
Cr='Craerman:BAAANQADCgYICwABNQAECgcIFQAGAAAAAQ==.Cranberrie:BAAANQADCggICAAAAA==.Crapo:BAAANQADCggIEgAAAA==.Cryhavok:BAABNQAECoEkAAMUAAkKARt9XwBPAgAUAAgKxRt9XwBPAgAVAAIKrg6b5ACEAAAAAA==.',
Cu='Cussack:BAABNQAECoEiAAINAAgKoyJwKQAEAwANAAgKoyJwKQAEAwAAAA==.Cutepandaa:BAAANQADCgQIBAAAAA==.',
Da='Dabubble:BAAANQADCgIIAgAAAA==.Dadaji:BAAANQADCgQIAQABNQAECgkJLQAPAFgcAA==.Daghar:BAAANQAECgIJAwAAAA==.Dalisaan:BAAANQADCgMIAwAAAA==.Dalé:BAAANQADCggICwAAAA==.Danastan:BAAANQAECgQICgAAAA==.Danui:BAAANQADCgQIBAAAAA==.Darkgol:BAAANQAECgUIBQABNQAECggIGgAUALYQAA==.Davioon:BAAANQAECgIIBQAAAA==.Dayrb:BAAANQAECgMIAwAAAA==.',
De='Deadlyheal:BAAANQADCgIIAgABNQADCggICAAGAAAAAA==.Deadtalini:BAABNQAECoEqAAMFAAkKgR2uEADrAgAFAAkKURyuEADrAgADAAcKtxm1MwAfAgAAAA==.Deah:BAAANQAECgQICQAAAA==.Deaththroes:BAAANQAECgQIBQAAAA==.Deckerdramon:BAABNQAECoEiAAIMAAgK6B31CACWAgAMAAgK6B31CACWAgAAAA==.Demomachin:BAABNQAECoEZAAIBAAgKARDqDgCXAQABAAgKARDqDgCXAQAAAA==.Demonnoodle:BAAANQADCggICQABNQAECgYIEgAGAAAAAA==.Demyze:BAAANQADCggIEAAAAA==.Densetsu:BAAANQADCgcJBwAAAA==.Destroyera:BAAANQAECgQIBAAAAA==.Deucalyon:BAAANQADCggIHgAAAA==.Devilchildd:BAAANQADCgMIAwAAAA==.Devours:BAACNQAFFIESAAIKAAUKSRnkBwC1AQAKAAUKSRnkBwC1AQA1AAQKgSEAAgoACQr6HAgnAKgCAAoACQr6HAgnAKgCAAAA.Devuledegg:BAAANQADCgEIAQAAAA==.',
Di='Dirtyhooves:BAAANQADCggIDwAAAA==.Divo:BAAANQADCgEIAgAAAA==.Diâblö:BAACNQAFFIERAAITAAUKqCV/AQAsAgATAAUKqCV/AQAsAgA1AAQKgSsAAhMACQr8Jg0AAAgEABMACQr8Jg0AAAgEAAAA.',
Do='Doesdrool:BAAANQADCgEIAQAAAA==.Dohtem:BAAANQADCgYICwABNQAECggIHQAJABAgAA==.Donmegah:BAAANQAECgUIDgAAAA==.Dotmoo:BAAANQADCgEIAQAAAA==.',
Dr='Dragibbay:BAAANQADCgUIBQAAAA==.Dragoncito:BAAANQADCgMIAwAAAA==.Dragusysmash:BAAANQAECgEIAQAAAA==.Draki:BAAANQADCgYIEAAAAA==.Drazzin:BAAANQADCgEIAQABNQAECgkJFwAWANETAA==.Dredtotem:BAAANQADCggICAAAAA==.Droodums:BAAANQAECgEIAQAAAA==.Druidmon:BAAANQADCgYICgAAAA==.',
Du='Duggo:BAAANQAECgUIEQAAAA==.Dutanu:BAAANQAECgQIBgABNQAECgcIHQAUAMIgAA==.',
Ei='Eibhlean:BAAANQAECgUIEwABNQAECgQIBwAGAAAAAA==.Eireckt:BAAANQADCgcIDAAAAA==.Eirrin:BAAANQAECgQIBAABNQAECgkJIAAQAEQiAA==.Eivorr:BAAANQABCgQJAgAAAA==.',
El='Elariin:BAAANQAECgUIDAAAAA==.Eleforever:BAABNQAECoEnAAIIAAkKfiEVEwBEAwAIAAkKfiEVEwBEAwABNQAECgkJJwAIAH4hAA==.Elendira:BAAANQADCgYIBgAAAA==.Ellektra:BAAANQABCgcIBwAAAA==.Elleredreaux:BAAANQAECgcICQAAAA==.',
Em='Emongar:BAAANQAECgQIBQAAAA==.',
En='Endomorphism:BAAANQAECgIIAgABNQAFFAYIEQAXAEkiAA==.',
Es='Estradiol:BAAANQADCgYICwAAAA==.',
Et='Etherhand:BAAANQADCgQIBAAAAA==.',
Ev='Evlynia:BAAANQADCgEIAQAAAA==.',
Ex='Exiza:BAAANQAECgMIBAAAAA==.',
Ez='Ezmelora:BAABNQAECoEeAAIYAAgKNg+kbQDuAQAYAAgKNg+kbQDuAQAAAA==.',
Fa='Fableshoot:BAAANQADCgQIBAAAAA==.Falconlaugh:BAAANQAECgEIAQAAAA==.Fancyrager:BAAANQADCgEIAQABNQADCgIIAgAGAAAAAA==.Fangtang:BAAANQAECggICAAAAA==.Fatherclutch:BAAANQADCgQICAABNQAECgUICQAGAAAAAA==.Fauxpawz:BAAANQADCgYICwAAAA==.Fayia:BAABNQAECoEkAAMQAAkKmxwbLADIAgAQAAkKmxwbLADIAgAZAAMK3ghTWgCWAAAAAA==.',
Fe='Felpal:BAAANQABCgMIAQABNQAECgYIHgAaAIALAA==.Felwoof:BAABNQAECoEnAAQWAAgKXCARDQBiAQAYAAUK2R4gggCzAQAWAAQKnR4RDQBiAQAbAAEKWCL0WwBlAAAAAA==.Felzak:BAAANQADCgYIBgABNQAECgIIAgAGAAAAAA==.Fentacide:BAAANQADCgMIAwAAAA==.',
Fi='Firewraith:BAAANQADCgYICwAAAA==.',
Fl='Flarllek:BAAANQADCgQICwAAAA==.Flexxed:BAABNQAECoEjAAIFAAkK/CHADgD/AgAFAAkK/CHADgD/AgAAAA==.',
Fo='Foopz:BAAANQADCgIJAgABNQAECgEIAQAGAAAAAA==.Forthehordde:BAAANQABCgcJCwAAAA==.',
Fr='Frakkinfrik:BAAANQABCgIIAgAAAA==.Freddybones:BAAANQAECgEIAgAAAA==.Frikkinfrak:BAAANQABCgIIAgAAAA==.Friskie:BAAANQAECgMJBAABNQAECgkJKAAcAGogAA==.Frostyxz:BAAANQADCgQIBAAAAA==.Fry:BAACNQAFFIERAAIOAAUKGRKFBgCRAQAOAAUKGRKFBgCRAQA1AAQKgSIAAg4ACQrOHG4SALoCAA4ACQrOHG4SALoCAAAA.Fríeren:BAAANQADCgIIAgAAAA==.',
Fu='Fubardruid:BAAANQADCgcIDwAAAA==.Fuguestate:BAAANQAECgYIEAAAAA==.Furystrike:BAABNQAECoEeAAMMAAgK3iT1BAAPAwAMAAgKNSP1BAAPAwANAAgKCR9kPAC+AgABNQAECgkJHAAUAGchAA==.',
Ga='Galenaa:BAAANQADCgUIBwAAAA==.Galixie:BAAANQABCgQIBgAAAA==.Ganondrow:BAABNQAECoEfAAMOAAgKkSFiDQAAAwAOAAgKkSFiDQAAAwAdAAEKng4LIgBAAAAAAA==.',
Ge='Gehagnute:BAAANQADCgEIAQAAAA==.Gemelo:BAAANQAECgcIEAAAAA==.Geromul:BAAANQADCgYICgAAAA==.Gerrexs:BAAANQAECgUIBQAAAA==.',
Gh='Ghst:BAAANQAECgcIBwAAAA==.',
Gi='Gibayy:BAAANQAECgUIDAAAAA==.Gibsonex:BAAANQAECgQIBwAAAA==.Gildagni:BAAANQADCgcIDAAAAA==.Gilliamm:BAABNQAECoEqAAMPAAkKCBSeIQCqAQAPAAYKVRaeIQCqAQARAAUKNBDrTgA4AQAAAA==.',
Gl='Gleste:BAAANQADCgQIBQAAAA==.',
Go='Golath:BAABNQAECoEaAAIUAAgKthDFiQDfAQAUAAgKthDFiQDfAQAAAA==.Gonguker:BAAANQADCgIIAgAAAA==.Gonthielhunt:BAAANQAECgMIBgAAAA==.Gothbutta:BAAANQAECgEIAQAAAA==.',
Gr='Grado:BAAANQADCgIIAgAAAA==.Grandena:BAAANQADCgUICgAAAA==.Graydeon:BAAANQAECgUIBQAAAA==.Greatangel:BAAANQADCgUIBAABNQAECgYIEQAGAAAAAA==.Gregano:BAAANQAECgQIBAABNQAECgkJHgANABALAA==.Gregorian:BAABNQAECoEeAAINAAkKEAs5kQDKAQANAAkKEAs5kQDKAQAAAA==.Gremliin:BAABNQAECoEvAAIcAAkKIiBfEAAvAwAcAAkKIiBfEAAvAwAAAA==.Grigo:BAAANQAECgIIBAAAAA==.Grippyt:BAAANQAECgEIAQAAAA==.Grymni:BAAANQADCgYIBgAAAA==.',
Ha='Hadesdecends:BAAANQADCgMIAwAAAA==.Halakal:BAAANQAECgIIAgAAAA==.Hammerbell:BAAANQAECggJCAAAAA==.Haviboomer:BAAANQADCgEIAQAAAA==.Havideeznuts:BAAANQADCggIEwAAAA==.',
He='Healmeharder:BAAANQADCgEIAQAAAA==.Healminth:BAAANQAFFAIIAgAAAA==.Healthcare:BAAANQAECgIIAgAAAA==.Hethar:BAAANQAECgEIAQAAAA==.',
Hi='Hierba:BAAANQADCggIDgAAAA==.Hightide:BAAANQAECgUIBQAAAA==.Hilltop:BAAANQABCgEJAQAAAA==.Hippo:BAAANQAECgYIEAAAAA==.',
Ho='Hoja:BAAANQAECgEIAgAAAA==.Holdor:BAAANQADCgEIAQAAAA==.Holdors:BAAANQADCggIDAAAAA==.Holier:BAAANQADCgYIBgABNQADCggJCAAGAAAAAA==.Holybloodboi:BAAANQAECgEJAQABNQAECgkJGwAKAEUhAA==.Holyfae:BAAANQADCgMIAwAAAA==.Holynoodle:BAAANQAECgEIBAABNQAECgYIEgAGAAAAAA==.',
Hy='Hymnbral:BAAANQAECgQIBAAAAA==.',
Ic='Iceberg:BAAANQADCgYIBgAAAA==.Icebergx:BAAANQADCgIIAwAAAA==.',
Il='Iliohae:BAAANQAECgQICwAAAA==.Illyssa:BAAANQADCgYICAAAAA==.',
Im='Imptricity:BAAANQAECgMIAwAAAA==.',
In='Insanegrippy:BAAANQAECgEIAQABNQAFFAYIFAAKAC0dAA==.Intaria:BAABNQAECoEoAAMNAAkKCRSZXgBTAgANAAkK2hOZXgBTAgAeAAMKlw6MHgCmAAAAAA==.Invisibulity:BAAANQADCgYICQABNQAECgYIHgAaAIALAA==.',
Is='Iseetouch:BAAANQABCgQIBAAAAA==.Isomorphism:BAAANQADCgYIBgAAAA==.',
It='Itchystraws:BAAANQAECgIIAgAAAA==.Itsrambo:BAAANQAECgQIBAAAAA==.',
Ja='Jackbeef:BAABNQAECoEjAAIeAAkKDh8UAwATAwAeAAkKDh8UAwATAwAAAA==.Jadedhooves:BAABNQAECoEWAAIUAAYKGgyF0ABAAQAUAAYKGgyF0ABAAQAAAA==.Jaggedlilhun:BAABNQAECoEZAAIQAAgK0w7YdwDxAQAQAAgK0w7YdwDxAQAAAA==.Jaggedshammy:BAAANQAECgUIBQABNQAECggIGQAQANMOAA==.Jagruk:BAAANQADCgIIAgABNQAECgIIAgAGAAAAAA==.Jareyk:BAABNQAECoEiAAIVAAgKDhaERgAtAgAVAAgKDhaERgAtAgAAAA==.Jarladorin:BAAANQAECgIIAgABNQAECgYIDgAGAAAAAA==.Jaxodk:BAABNQAECoEZAAIEAAgKKyODEgAOAwAEAAgKKyODEgAOAwAAAA==.',
Jb='Jbrealone:BAAANQADCgMIAwAAAA==.',
Je='Jecka:BAAANQAECgEIAgAAAA==.Jedai:BAABNQAECoEyAAIVAAkKqx6kFwAKAwAVAAkKqx6kFwAKAwAAAA==.Jellybeann:BAAANQADCgQICwAAAA==.Jerrysix:BAABNQAECoEYAAMOAAcKbBZZJADlAQAOAAcKbBZZJADlAQAdAAMKgAdVGQCGAAAAAA==.',
Ji='Jilseponie:BAAANQABCgIIAgABNQAECgcICAAGAAAAAA==.Jimmypop:BAAANQADCggIEAAAAA==.',
Ju='Judadiah:BAAANQAECgYIDgAAAA==.Judo:BAAANQAECgUICQAAAA==.Justbeginner:BAAANQADCggIEAAAAA==.',
Jy='Jyloti:BAAANQAECgIIAgAAAA==.',
['Jà']='Jàxx:BAAANQAECgUICQAAAA==.',
['Jä']='Jänice:BAAANQAECggIAQAAAA==.',
['Jå']='Jåggy:BAAANQADCgYIBgABNQAECggIGQAQANMOAA==.',
Ka='Kaego:BAAANQADCgcIAgABNQAECggIGwAfABkSAA==.Kalona:BAAANQADCgQIBAAAAA==.Kalrock:BAAANQAECgcIEgAAAA==.Kalrotten:BAAANQADCgcICgABNQAECgcIEgAGAAAAAA==.Kalulu:BAAANQADCggIGQAAAA==.Kalyssi:BAAANQAECgMIAwAAAA==.Kancisa:BAAANQAECgEIAQAAAA==.Karkit:BAAANQADCgYIFQAAAA==.Katkot:BAAANQAECgcIEgAAAA==.Kayro:BAAANQADCgUICAAAAA==.Kazlan:BAAANQAECgMIAwAAAA==.Kazzulee:BAAANQADCgEIAQAAAA==.',
Ke='Keledrian:BAAANQADCgQIBAAAAA==.Keres:BAACNQAFFIEHAAIDAAMK+iMjDgBAAQADAAMK+iMjDgBAAQA1AAQKgSYAAgMACQqBJFwFAJQDAAMACQqBJFwFAJQDAAAA.',
Kh='Khagolith:BAABNQAECoEbAAIfAAgKGRIhOgD2AQAfAAgKGRIhOgD2AQAAAA==.',
Ki='Kioria:BAAANQADCgcIDQAAAA==.Kirishino:BAAANQADCggIFAAAAA==.Kizzazz:BAAANQADCgQIBAAAAA==.',
Kk='Kkodabear:BAAANQAECgEIAQAAAA==.',
Kl='Klixeas:BAAANQADCgIIAgAAAA==.',
Ko='Kobiter:BAABNQAECoEZAAQVAAcK4ww+fQB4AQAVAAcK4ww+fQB4AQAUAAYKPA6NyQBPAQAgAAQKPg7YRAC0AAABNQAECgkJJQAMAA0hAA==.Kobito:BAABNQAECoElAAMMAAkKDSHdAwA5AwAMAAkKDSHdAwA5AwANAAYK3RLZpACVAQAAAA==.Korvas:BAAANQABCgMIAQAAAA==.Koup:BAABNQAECoEuAAMQAAkKPSV+AwDGAwAQAAkKPSV+AwDGAwAZAAEKfhL8fAAzAAAAAA==.Koupe:BAABNQAECoEYAAMhAAcKHxOXLgBwAQAhAAYKOROXLgBwAQAfAAUK/xHcZAAPAQABNQAECgkJLgAQAD0lAA==.',
Kr='Krang:BAAANQAECgIIAQAAAA==.Kranx:BAAANQADCgUIBQAAAA==.Krayzebeef:BAAANQAECgQIDwABNQAECgUIDgAGAAAAAA==.Kriss:BAAANQAECgQICAAAAA==.',
Ku='Kungfudk:BAAANQADCgQIBAAAAA==.Kupe:BAAANQADCgUIBQABNQAECgkJLgAQAD0lAA==.Kurirne:BAAANQADCgQIBQAAAA==.',
Ky='Kyewanda:BAAANQAECgYIDAAAAA==.Kyusakuu:BAAANQAECgYIDAAAAA==.',
La='Laanu:BAAANQAECgIIAgABNQAECgUIBQAGAAAAAA==.Lahey:BAABNQAECoEoAAINAAkKoQ+nbwAjAgANAAkKoQ+nbwAjAgAAAA==.Lakes:BAAANQAECgYIDgAAAA==.Lanuna:BAAANQAECgMIAwAAAA==.Lathara:BAAANQAECgUIDgAAAA==.Lavs:BAABNQAECoESAAIiAAYKzR9IDAArAgAiAAYKzR9IDAArAgAAAA==.Laxkeeper:BAAANQADCgUIBwAAAA==.',
Le='Legostepper:BAAANQADCgMIAwAAAA==.Leronis:BAAANQAECgcIEQAAAA==.Lexiah:BAAANQAECgUIDAAAAA==.',
Li='Lilicyhot:BAAANQADCgcIDAAAAA==.Lilliana:BAAANQAECgEIAQABNQAECgQIBwAGAAAAAA==.Linneasage:BAAANQADCgQIBAAAAA==.Lizardbrain:BAAANQAECgMIBwAAAQ==.',
Lo='Loamathor:BAAANQADCggIJQAAAA==.Loesh:BAAANQADCgIJAgAAAA==.Lorilyn:BAABNQAECoEYAAIcAAcK+xtAQQBBAgAcAAcK+xtAQQBBAgAAAA==.Lorthag:BAABNQAECoEgAAIdAAcKVhOsCAC+AQAdAAcKVhOsCAC+AQAAAA==.Lovebuz:BAAANQADCgYIBgAAAA==.Loveles:BAAANQADCggICAAAAA==.Loverone:BAAANQADCgIIAgAAAA==.Loyalty:BAAANQADCggIDwAAAA==.',
Lu='Lucciola:BAAANQADCgQIBAAAAA==.Lulbah:BAAANQAECgUIEAAAAA==.Lunareclips:BAAANQADCgMIAwAAAA==.Lunarus:BAABNQAECoEZAAIWAAcK/wsfCwCTAQAWAAcK/wsfCwCTAQAAAA==.',
['Lì']='Lìfe:BAABNQAECoEaAAINAAgKTBMvfgD8AQANAAgKTBMvfgD8AQAAAA==.',
['Ló']='Lónnie:BAAANQAECgMIAwAAAA==.Lónnìe:BAAANQAECgYIDwAAAA==.Lónníe:BAAANQAECgQICQAAAA==.',
Ma='Macloving:BAAANQAECgQIBwAAAA==.Maelona:BAAANQAECgYICQAAAA==.Maen:BAAANQADCgcIBwAAAA==.Magrumok:BAAANQAECgYIDQAAAA==.Magthars:BAAANQAECgIIAgAAAA==.Magtide:BAABNQAFFIEHAAIZAAMKCBm0EQDsAAAZAAMKCBm0EQDsAAAAAA==.Malväryx:BAAANQAECgQICwAAAA==.Manbearpig:BAABNQAECoEnAAIQAAkKEiMyDgBdAwAQAAkKEiMyDgBdAwAAAA==.Manman:BAAANQAECgMIBAAAAA==.Marshes:BAAANQADCgIIAgABNQAECgYIDgAGAAAAAA==.Masshooter:BAAANQAECgEIAQAAAA==.Mazirek:BAAANQADCgMIAwAAAA==.',
Mc='Mctigly:BAAANQAECgUICgAAAA==.',
Me='Megadefi:BAAANQAECgEIAQAAAA==.Megol:BAAANQADCggIDQAAAA==.Melirraei:BAAANQADCgYIDAAAAA==.Melith:BAAANQADCgYIBgAAAA==.Melkiel:BAABNQAECoEnAAILAAgK1h1pbwCJAgALAAgK1h1pbwCJAgAAAA==.Mellindre:BAAANQAECgIIAgAAAA==.Meltman:BAAANQABCgIIAgAAAA==.Mentalmidget:BAABNQAECoEaAAIgAAgKqwyDKgBdAQAgAAgKqwyDKgBdAQAAAA==.Mesa:BAABNQAECoFaAQMjAAkKgSYNAAAOBAAjAAkKgSYNAAAOBAAaAAEKGhLNNABGAAAAAA==.Methaen:BAAANQADCgEIAQAAAA==.',
Mi='Miclovin:BAABNQAECoEiAAMPAAkKShjiCwCnAgAPAAkKQRjiCwCnAgARAAIKBwW/fgBZAAAAAA==.Microplastic:BAABNQAECoElAAMNAAkK8xkDQgCrAgANAAkK8xkDQgCrAgAMAAUKYRVTIAAeAQAAAA==.Midsized:BAAANQADCgIIAgAAAA==.Mikexz:BAAANQADCgEIAQAAAA==.Mikoani:BAABNQAECoEfAAIEAAcKSht7QAD1AQAEAAcKSht7QAD1AQAAAA==.Minigunn:BAAANQADCggIEAAAAA==.Mirumahn:BAAANQADCgUIBwAAAA==.Misocursed:BAAANQADCgYIEwAAAA==.Misoquick:BAAANQAECgMIAwAAAA==.Misosmol:BAAANQAECgIIAwAAAA==.Missogyny:BAABNQAECoEbAAILAAgKVBxYXgCvAgALAAgKVBxYXgCvAgAAAA==.Mithunzi:BAAANQAECgYIDQAAAA==.',
Mo='Moadeab:BAAANQADCggIHQAAAA==.Mogando:BAAANQAECgEIAQABNQAECgkJFwAWANETAA==.Mogrodeath:BAAANQAECgIIAQAAAA==.Mogrodrag:BAAANQADCggICAABNQAECgkJHwAYAGAbAA==.Mogrodruid:BAAANQADCgYIBgABNQAECgkJHwAYAGAbAA==.Mogrogarg:BAABNQAECoEfAAMYAAkKYBvbWQAoAgAYAAcK5xnbWQAoAgAbAAQKrBqGJQA9AQAAAA==.Mogrosham:BAAANQAECgEIAwAAAA==.Mogrougarg:BAAANQAECgIIAgABNQAECgkJHwAYAGAbAA==.Mojojojò:BAAANQAECgMIAwAAAA==.Momimilkers:BAAANQADCgcIDAABNQAECgkJKgAkAG4bAA==.Mommasha:BAAANQADCgQIBAAAAA==.Monkky:BAAANQADCgYIBgAAAA==.Moonshift:BAAANQAECggICAAAAA==.Mordin:BAAANQADCgcICwAAAA==.Morenthia:BAAANQAECgUIBQAAAA==.Moribelar:BAAANQAECgQIBgAAAA==.Mormonhunter:BAAANQAECgEIAQAAAA==.Morriffic:BAAANQAECgYICgABNQAECgkJHgAhAFweAA==.Morventhas:BAAANQADCgIIAgAAAA==.Mosshead:BAAANQADCggIDwAAAA==.Mousethyr:BAAANQAECgYIDgAAAA==.Mousyz:BAAANQADCgIIAgAAAA==.',
Mu='Muahah:BAAANQAECgEIAgAAAA==.Munric:BAABNQAECoEkAAIUAAgKQwbjwwBbAQAUAAgKQwbjwwBbAQAAAA==.Munusku:BAAANQAECgUIBQAAAA==.',
My='Myboycleetus:BAAANQAECgUIDAAAAA==.Mylocky:BAAANQAECgEIAQAAAA==.Mynon:BAAANQADCgMIAwAAAA==.',
['Mä']='Mäze:BAAANQADCgYIBgAAAA==.',
['Mé']='Méudäil:BAAANQAECgQICAAAAA==.',
['Mï']='Mïkasa:BAAANQAECgQIBAAAAA==.',
Na='Nachobussy:BAABNQAFFIEMAAMZAAUKow9ACwBkAQAZAAUKwA1ACwBkAQAQAAMK/RO1EwD1AAAAAA==.Nachothings:BAABNQAECoEYAAMlAAkKWxbNHQBGAgAlAAkKWxbNHQBGAgACAAEKVhnjfQBAAAABNQAFFAUIDAAZAKMPAA==.Nautico:BAAANQADCgUJBQAAAA==.',
Ne='Necrokat:BAAANQAECgMIBwAAAA==.Nephelia:BAAANQADCgYIBgAAAA==.Ner:BAAANQAECgQIBAAAAA==.Nezha:BAAANQAECgEJAQABNQAECggIGQAYAD4kAA==.',
Ni='Nightmist:BAAANQADCggIIwAAAA==.Nihility:BAABNQAECoEZAAMYAAgKPiRbKADLAgAYAAcKKyRbKADLAgAbAAIKuiBAQwCtAAAAAA==.Ninobrown:BAAANQAECgEIAQAAAA==.Nirgand:BAAANQAECgEIAQABNQAECgkJFwAWANETAA==.Nitak:BAAANQAECggICAAAAA==.',
No='Nokoan:BAAANQAECgEIAQAAAA==.Noodlestang:BAAANQAECgYIEgAAAA==.Nool:BAAANQAECgEIAQAAAA==.Norest:BAAANQADCggICAAAAA==.Norgand:BAABNQAECoEXAAMWAAkK0RP3BwDwAQAWAAcK7RX3BwDwAQAYAAIKbwzyCAF3AAAAAA==.Noriboness:BAAANQAECgQIBgAAAA==.Nosleep:BAABNQAECoEmAAIMAAkKyBfACwBQAgAMAAkKyBfACwBQAgAAAA==.Notdumb:BAAANQADCgUJDAAAAA==.',
Nu='Nullify:BAAANQADCgUICQAAAA==.',
Ny='Nydeath:BAAANQAECgMIAwAAAA==.Nyduss:BAAANQAECgMIBwAAAA==.Nymphs:BAAANQADCgEIAQABNQAECgcIHAAcANQaAA==.Nyraxys:BAABNQAECoEUAAIjAAcKHQw8JQBzAQAjAAcKHQw8JQBzAQAAAA==.Nyxpal:BAAANQAECgIIAgAAAQ==.',
['Nù']='Nùtter:BAAANQADCgMIAwAAAA==.',
Ob='Obalo:BAAANQADCgcICQAAAA==.Obrlord:BAAANQADCgcIDwAAAA==.',
Oc='Ocopoko:BAAANQADCgcIBwAAAA==.',
Od='Oddzmage:BAAANQAECgYICgAAAA==.',
On='Onibushi:BAABNQAECoEfAAINAAgKcBqUVABxAgANAAgKcBqUVABxAgAAAA==.',
Oo='Oof:BAAANQAECgMJAwAAAA==.',
Op='Ophinias:BAAANQADCgcICAAAAA==.Optimize:BAABNQAECoEfAAILAAkKaxu1RgDnAgALAAkKaxu1RgDnAgAAAA==.',
Or='Orastal:BAAANQAECgcIEQAAAA==.Ordonoir:BAAANQAECgIIAgAAAA==.Oruun:BAABNQAECoFjAAIIAAgK3CTDDgBmAwAIAAgK3CTDDgBmAwAAAA==.',
Pa='Paid:BAAANQADCgQIBAAAAA==.Palledized:BAAANQADCgcICAAAAA==.Paloadin:BAAANQAECgQICwAAAA==.Pameliana:BAAANQAECgUIBQABNQABCgYIBwAGAAAAAA==.Pandadander:BAAANQADCgYIBgABNQAECgUIDAAGAAAAAA==.Pandalo:BAAANQADCgcIEAAAAA==.Pandalock:BAAANQAECgcICAAAAA==.Parasiite:BAAANQAECgYIDwAAAA==.Parasíte:BAAANQABCggICAABNQAECgYIDwAGAAAAAA==.',
Pe='Peepocute:BAABNQAECoEYAAMlAAcKPxtHJwDqAQAlAAcKJBZHJwDqAQACAAYKuRCXSABNAQAAAA==.Peghane:BAAANQADCgQIBgAAAA==.Pelarn:BAAANQADCgUIBQAAAA==.',
Ph='Phadenstar:BAAANQADCgQICAAAAA==.Phylus:BAAANQAECgQICAAAAA==.Physiowar:BAABNQAECoEbAAINAAcKZhcajQDVAQANAAcKZhcajQDVAQAAAA==.',
Pi='Pickledeath:BAAANQAECgQIBgAAAA==.Pilik:BAAANQABCgYIBgAAAA==.Pizzapuff:BAAANQADCgYICwAAAA==.',
Pl='Plaguemachin:BAAANQADCgMIAwAAAA==.',
Po='Ponchoe:BAAANQADCgQIBQAAAA==.Poobahdrag:BAABNQAECoEsAAMjAAkK7iMMAgCeAwAjAAkK7iMMAgCeAwAaAAIKMQp5MABsAAAAAA==.Popster:BAAANQADCgYICwAAAA==.Poundpup:BAAANQADCgcIBwAAAA==.',
Pr='Prell:BAAANQAECgMIAwAAAA==.Preservation:BAAANQAECgcIEAAAAA==.Prodipriest:BAAANQAECgcICAAAAA==.',
Pu='Puffdragon:BAAANQADCgIIAgAAAA==.Pugi:BAAANQADCgEIAQAAAA==.Putridstrike:BAAANQAECggICQABNQAECgkJHAAUAGchAA==.',
Qt='Qtiy:BAAANQAECgUIBQABNQAECgcIFwANAHccAA==.Qtyy:BAABNQAECoEXAAINAAcKdxxVXABaAgANAAcKdxxVXABaAgAAAA==.',
Qu='Quantaboom:BAAANQADCgYIBgAAAA==.',
Ra='Raawwrr:BAAANQADCggIFAAAAA==.Rabbi:BAAANQADCgIIAQAAAA==.Racken:BAAANQAECgMIBgAAAA==.Raegyr:BAAANQADCgQIBAAAAA==.Ragehound:BAAANQADCgYJBwAAAA==.Rainhealz:BAAANQADCgIIAgAAAA==.Ramped:BAAANQAECgQICQAAAA==.Ranzor:BAAANQAECgcIEAAAAA==.Rashis:BAAANQAECgMIBAAAAA==.Rattpack:BAAANQAECgEIAQAAAA==.Raveyn:BAAANQAECgYIEAAAAA==.',
Re='Redjak:BAAANQADCggIEAAAAA==.Regino:BAAANQAECgUIEgAAAA==.Reitiado:BAAANQADCgIIAgAAAA==.Rekieuwu:BAAANQADCgYIBgABNQAECggIGAAQAPgQAA==.Rekita:BAABNQAECoEYAAIQAAgK+BBNcAADAgAQAAgK+BBNcAADAgAAAA==.Remedi:BAAANQAECgYICgAAAA==.Retaxus:BAAANQABCgEJAQAAAA==.Retispagheti:BAAANQADCggJCAAAAA==.Retnuh:BAABNQAECoEZAAIQAAgKqg6CfgDhAQAQAAgKqg6CfgDhAQAAAA==.Revivified:BAAANQADCgcIBwAAAA==.',
Rh='Rhibbons:BAAANQADCgEIAQAAAA==.Rhyneaux:BAAANQAECgIIAgAAAA==.',
Ri='Rimmjab:BAAANQADCgcIBwAAAA==.Rivén:BAAANQADCggICAABNQAECgUICQAGAAAAAA==.',
Rn='Rn:BAAANQAECgUICQAAAA==.',
Ro='Rockypalboa:BAAANQADCgcIBwAAAA==.Roderika:BAAANQADCgcIDgABNQAFFAMIBwADAPojAA==.Roldin:BAAANQAECgEIAQAAAA==.Rolockrad:BAAANQAECgYIEwAAAA==.Romanflak:BAAANQAECgIIAgAAAA==.Roostr:BAABNQAECoEgAAIbAAgK5BNWCwA3AgAbAAgK5BNWCwA3AgAAAA==.Rord:BAABNQAECoEaAAMUAAgK7BuUWQBgAgAUAAgK7BuUWQBgAgAVAAEKvxQYAgE8AAAAAA==.Royjacked:BAAANQAECgMIBAAAAA==.',
Ru='Rubberr:BAAANQAECgQICQAAAA==.Rubbershank:BAAANQAECgIIAwAAAA==.Rufío:BAAANQAECgMIAwAAAA==.Rumblebee:BAAANQAECgIIBAAAAA==.Runicstrike:BAABNQAECoE3AAQEAAkKNyXUCQBdAwAEAAkK4SPUCQBdAwADAAYKqx65QADcAQAFAAUKYBjxUwASAQABNQAECgkJHAAUAGchAA==.',
['Rø']='Røøm:BAAANQADCgYIBgAAAA==.',
Sa='Sackakt:BAAANQADCggIDQAAAA==.Sadie:BAAANQAECgQIBAABNQAECggIHwAKAOglAA==.Sagalia:BAAANQADCgIIAgABNQAECggICAAGAAAAAA==.Sahra:BAABNQAECoEfAAIKAAgK6CV8CgBZAwAKAAgK6CV8CgBZAwAAAA==.Sanctustrike:BAABNQAECoEcAAMUAAkKZyEMSACWAgAUAAgKjR8MSACWAgAgAAYKqR5xHQDTAQAAAA==.Saraphina:BAAANQAECgQIBwAAAA==.Sauruman:BAAANQADCgEIAQAAAA==.Sayge:BAAANQABCgMIBAAAAA==.',
Se='Sellandre:BAAANQAECgcIDwAAAA==.Selvalamhi:BAAANQADCgQIBAABNQAECgkJFwAWANETAA==.Seronja:BAAANQAECgQIBwAAAA==.Serpompom:BAAANQADCgUIBQAAAA==.',
Sh='Shazzai:BAAANQAECgQICQAAAA==.Sherfight:BAABNQAECoEoAAMcAAkKaiAlCABxAwAcAAkKaiAlCABxAwAOAAMKiRNOTgCwAAAAAA==.Shielddaddy:BAAANQAECgIIBgAAAA==.Shieldsftl:BAAANQAECgYIDgABNQAECgcICAAGAAAAAA==.Shiftycent:BAAANQAECggIAQAAAA==.Shnyaga:BAABNQAECoFZAQQcAAkKMyX2AADdAwAcAAkKMyX2AADdAwAOAAQKtB83MQBwAQAdAAIKQRX9FwCWAAAAAA==.Shockybalboa:BAAANQAECgQIBAAAAA==.Shrider:BAAANQADCgYIDAAAAA==.Shunkd:BAAANQAECgUIBQAAAA==.Shøcker:BAAANQADCgEIAQAAAA==.',
Si='Sianda:BAAANQABCgQIBAAAAA==.Silithaine:BAAANQADCgUIBQAAAA==.Simpsforimps:BAAANQAECgEIAQAAAA==.Sinsanityz:BAAANQAECggIDgAAAA==.Sixxsevenn:BAAANQADCgcIBwAAAA==.Sizurp:BAAANQABCgIIAgAAAA==.',
Sj='Sjardags:BAAANQAECgQIBAAAAA==.',
Sk='Skinwalk:BAAANQAECgQICwAAAA==.Skrai:BAAANQAECgQIBQAAAA==.',
Sl='Sleew:BAABNQAECoEqAAMYAAkKFRpVPgB8AgAYAAgK1xlVPgB8AgAbAAIKJRNCTwCFAAAAAA==.Slippydippy:BAAANQAECgEIAQAAAA==.',
Sn='Sneakylizard:BAAANQADCgYICwAAAA==.Snocaps:BAAANQADCgYIBgAAAA==.',
So='Soggypringle:BAAANQAECgEIAQAAAA==.Solary:BAAANQADCgIIAgAAAA==.Solnath:BAABNQAECoEmAAICAAkKJiKqBwBvAwACAAkKJiKqBwBvAwAAAA==.Souldaddy:BAAANQAECgUIBgAAAA==.',
Sp='Spankinstien:BAAANQADCggIDgAAAA==.Specsdraco:BAABNQAECoEsAAIZAAkK8iL5AwCPAwAZAAkK8iL5AwCPAwAAAA==.Spewpuke:BAABNQAECoEqAAMMAAkKRx/2BAAPAwAMAAkKRx/2BAAPAwANAAcKvRE6kwDEAQAAAA==.Spicytomato:BAABNQAECoEiAAMWAAgKdyBCAgDpAgAWAAgKdyBCAgDpAgAbAAEKTxcLbQA9AAAAAA==.Spirtforge:BAAANQADCgYIBgAAAA==.',
St='Staci:BAAANQAECgEIAQAAAA==.Starfree:BAABNQAECoEgAAIcAAkK2xEbRwArAgAcAAkK2xEbRwArAgAAAA==.Starstorm:BAAANQADCgQIBAABNQAECgkJKgAYABUaAA==.Stgermain:BAABNQAECoEjAAMcAAkKmRpXIQDNAgAcAAkKmRpXIQDNAgAOAAYKQhVDLQCSAQAAAA==.Stinkybinks:BAAANQADCgcIBgAAAA==.Stormlotus:BAAANQAECgMIBwAAAA==.Stormsorrow:BAAANQAECgUICgAAAA==.Strikeanywer:BAAANQAECgIIAgAAAA==.',
Su='Superstoned:BAAANQADCgIJAgAAAA==.Surudk:BAAANQAECgUIBgAAAA==.',
Sy='Sylrana:BAAANQAECgQIBgAAAA==.Sylri:BAAANQADCgYIBgAAAA==.',
Ta='Takticel:BAAANQAECgEIAQAAAA==.Taktikal:BAAANQADCggICAABNQAECgEIAQAGAAAAAA==.Taktikil:BAAANQADCgYIEwABNQAECgEIAQAGAAAAAA==.Talrad:BAAANQAECgQIBgAAAA==.Tamale:BAAANQAECggIBQAAAA==.Tazerxface:BAABNQAECoEsAAIKAAkKnRZ6MQB1AgAKAAkKnRZ6MQB1AgAAAA==.',
Te='Tealgos:BAABNQAECoEeAAIaAAYKgAsKIAA4AQAaAAYKgAsKIAA4AQAAAA==.Teenyhands:BAAANQAECgQICAAAAA==.Teldrasa:BAAANQAECgQIBQAAAA==.Telerein:BAAANQADCgMIAwABNQAECgQIBgAGAAAAAA==.Tewtz:BAAANQADCgQIBAAAAA==.',
Th='Thaiddous:BAABNQAECoEdAAIXAAgK7h0ACQCzAgAXAAgK7h0ACQCzAgAAAA==.Thanx:BAAANQAECgIIAgAAAA==.Thebeefchief:BAACNQAFFIEKAAIXAAQKvR+tAQB8AQAXAAQKvR+tAQB8AQA1AAQKgRsAAhcACQpaIs8DAFUDABcACQpaIs8DAFUDAAAA.Thebigmon:BAABNQAECoEkAAIIAAgKeB71KQC1AgAIAAgKeB71KQC1AgAAAA==.Thedabara:BAAANQADCgQIBgAAAA==.Thedon:BAAANQAECgUIDAAAAA==.Therealnmula:BAAANQADCgUICgAAAA==.Thewhite:BAAANQAECgcICwAAAA==.Thorxx:BAAANQADCgYICwAAAA==.Thrudtotems:BAAANQAECgcICwAAAA==.Thrudx:BAAANQAECgYIEAAAAA==.Thugnastie:BAAANQAECgYIEgAAAA==.Thylia:BAAANQADCgYIBgAAAA==.',
Ti='Tika:BAAANQAECgUIDwAAAA==.Timeisdruid:BAAANQAECgEIAQAAAA==.Tinytina:BAAANQAECgYIBwAAAA==.',
To='Toastyshamy:BAAANQAECgIIAgAAAA==.Tofrenm:BAAANQAECgUIDAAAAA==.Togashi:BAABNQAECoEfAAImAAgKfiAhDwDUAgAmAAgKfiAhDwDUAgAAAA==.Toof:BAAANQAECgIIAgAAAA==.Topacio:BAAANQADCggIGgAAAA==.Topnacho:BAAANQADCgEIAQABNQAFFAUIDAAZAKMPAA==.Torskeprime:BAAANQADCgEIAQAAAA==.Totalpyro:BAAANQAECgUIEQAAAA==.Toymueto:BAAANQAECgQIBAAAAA==.',
Tr='Treespirit:BAAANQAECgcIEgAAAA==.Trenbologne:BAAANQADCgMIAwAAAA==.Tricep:BAAANQADCggIGAAAAA==.Tripallie:BAAANQADCgYIFAAAAA==.Trishian:BAAANQAECgEIAQAAAA==.Trunkmuffin:BAAANQAECgEIAQAAAA==.Truthless:BAEBNQAECoEmAAIVAAkKESDyCwBaAwAVAAkKESDyCwBaAwAAAA==.',
Tu='Tuckermax:BAAANQAECgIIAgAAAA==.Tunks:BAAANQAECgYIDwAAAA==.Tusk:BAABNQAECoEYAAIKAAgKEB8FKgCYAgAKAAgKEB8FKgCYAgAAAA==.',
Ty='Tyranbae:BAAANQADCggICAABNQAECgkJLAAjAO4jAA==.',
Ug='Uglyashell:BAAANQAECgEIAQAAAA==.',
Un='Unit:BAABNQAECoEeAAIJAAgKiSCSBwD1AgAJAAgKiSCSBwD1AgAAAA==.',
Uv='Uva:BAAANQAECgUIBwAAAA==.',
Va='Valanui:BAAANQADCgIIAgAAAA==.Valendara:BAABNQAECoEXAAIWAAgKRxPPBgAVAgAWAAgKRxPPBgAVAgAAAA==.Valsorin:BAAANQAECgQIBwAAAA==.Valtaea:BAABNQAECoEjAAILAAkKUg8fmAAyAgALAAkKUg8fmAAyAgAAAA==.',
Ve='Velanthos:BAAANQAECgEIAQAAAA==.Vershammy:BAAANQAECgEIAQAAAA==.',
Vi='Vishas:BAAANQADCgMIAwAAAA==.Vixol:BAAANQADCgQJBAAAAA==.',
Vo='Voidheals:BAAANQADCgEIAQABNQAECgUIDgAGAAAAAA==.Voidwaffle:BAAANQADCgcIDQAAAA==.Volairne:BAAANQADCgQIBwAAAA==.Voreah:BAAANQAECgEIAgABNQAECgQICgAGAAAAAA==.',
Wa='Wafflxs:BAACNQAFFIEIAAITAAUKZB8rAwCxAQATAAUKZB8rAwCxAQA1AAQKgSQAAhMACQrNJG0CAIcDABMACQrNJG0CAIcDAAAA.Walkingheals:BAAANQADCgIIAwAAAA==.Wanpisu:BAABNQAECoEaAAIUAAgKLBlvbwAjAgAUAAgKLBlvbwAjAgAAAA==.Warglave:BAAANQAECgQIBAAAAA==.Warmo:BAAANQADCggICAAAAA==.Warunk:BAAANQAECggIEwAAAA==.',
Wc='Wcldragon:BAAANQADCgUIBgAAAA==.',
We='Weiwu:BAACNQAFFIEJAAImAAQKmwqvCAARAQAmAAQKmwqvCAARAQA1AAQKgSsAAiYACQpTH0ULAAkDACYACQpTH0ULAAkDAAAA.Wellfookthat:BAABNQAECoEnAAIKAAkKPSG+DABGAwAKAAkKPSG+DABGAwAAAA==.Wellfookyew:BAAANQADCgcIBwABNQAECgkJJwAKAD0hAA==.Weolf:BAAANQABCgIIAQAAAA==.',
Wh='Whiteshadows:BAAANQAECgUIEgAAAA==.Whyvala:BAAANQAECgYIBgABNQADCggIFgAGAAAAAA==.Whyvara:BAAANQADCggIFgAAAA==.',
Wi='Wiisp:BAAANQAECgYIEwAAAA==.',
Wo='Wolnney:BAABNQAECoEtAAIUAAkKviUfAwDeAwAUAAkKviUfAwDeAwAAAA==.Wowimhealing:BAAANQADCgcIEAAAAA==.',
Wr='Wrath:BAAANQADCgQIBAAAAA==.',
Wu='Wubnah:BAAANQADCgIIAgAAAA==.',
['Wâ']='Wâarseer:BAAANQADCgcIEgAAAA==.',
Xa='Xalatoes:BAACNQAFFIEUAAIKAAYKLR3HAwAoAgAKAAYKLR3HAwAoAgA1AAQKgSUAAgoACQojISsXAP4CAAoACQojISsXAP4CAAAA.Xanathar:BAAANQADCgYICAAAAA==.Xandertheone:BAAANQADCgUIBQAAAA==.Xandrin:BAAANQAECgIIAgAAAA==.',
Xi='Xionglieren:BAAANQADCgQIBAABNQADCggIHAAGAAAAAA==.Xiren:BAAANQABCgIJBAAAAA==.',
Xr='Xraiz:BAAANQAECgQIBgAAAA==.',
Xy='Xyne:BAAANQADCggIEQAAAA==.',
Ya='Yakiwhack:BAAANQADCgEIAQAAAA==.',
Yo='Yogonine:BAACNQAFFIEIAAITAAMK6hraBQAGAQATAAMK6hraBQAGAQA1AAQKgTAAAhMACQpUJAwCAJQDABMACQpUJAwCAJQDAAAA.Yourboyblue:BAAANQADCgYIFgAAAA==.',
Yv='Yverrius:BAAANQADCgMICAAAAA==.',
Za='Zanydruid:BAAANQADCgQICAAAAA==.Zanza:BAAANQAECgUIDAAAAA==.Zarione:BAAANQADCgYIBgAAAA==.',
Ze='Zearyth:BAAANQADCgcIDQAAAA==.Zemus:BAAANQADCggIEQAAAA==.Zenevieva:BAAANQADCgIIAgAAAA==.',
Zh='Zhamazu:BAAANQADCgUIBwAAAA==.Zharost:BAAANQADCgUIBgAAAA==.Zhayden:BAABNQAECoEWAAIPAAcKWxaPGAAFAgAPAAcKWxaPGAAFAgAAAA==.Zhy:BAAANQAECgMIAwAAAA==.Zhygår:BAAANQAECgEIAQAAAA==.',
Zi='Ziberia:BAAANQADCgIIAgAAAA==.Zidenko:BAAANQAECgQIBgAAAA==.',
Zo='Zodin:BAAANQADCggIGwABNQAECgYICQAGAAAAAA==.Zombiez:BAABNQAECoEOAAIEAAYKFAmgeQALAQAEAAYKFAmgeQALAQAAAA==.Zoryn:BAAANQADCggIFAABNQADCggICAAGAAAAAA==.',
Zw='Zwerlin:BAAANQAECgEIAQAAAA==.',
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
