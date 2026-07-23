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

local lookup = {'Druid-Restoration','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Warlock-Affliction','DeathKnight-Blood','Priest-Discipline','Monk-Brewmaster','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abrácadabra:BAAALgAECgMJAwABLgAECgkJPwABAOgVAA==.',
Ac='Achilles:BAABLgAFFH8IAAMCAAUJRgxEIgDvAAACAAUJCQtEIgDvAAADAAEJSgh/EAAkAAAAAA==.',
Ad='Aderan:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAAEAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJMwAFAAYhAA==.Aesalon:BAABLgAECn80AAQGAAkJ1CMHBADHAgAGAAkJ1CMHBADHAgAHAAIJrRTjeQA+AAAIAAIJGBMIcwA0AAABLgAECgkJHgAJAOEdAA==.',
Ah='Ahsokatano:BAABLgAECn8zAAMFAAkJBiFuBwA5AwAFAAkJBiFuBwA5AwAKAAEJ8gwQswAnAAAAAA==.',
Ai='Aimspet:BAABLgAECn8WAAIFAAYJmBOKXwA+AQAFAAYJmBOKXwA+AQAAAA==.Aircanada:BAAALgAECgIJBAAAAA==.',
Ak='Akela:BAABLgAECn8oAAILAAkJIQ1sTQC6AQALAAkJIQ1sTQC6AQAAAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAABLgAECn8YAAICAAcJBxQLEQAoAQACAAcJBxQLEQAoAQAAAA==.Amonet:BAABLgAECn8aAAIMAAYJnQqLHADJAAAMAAYJnQqLHADJAAAAAA==.',
An='Anaelcheese:BAABLgAECn8cAAQNAAcJ1xoPIwBfAQANAAcJ1xoPIwBfAQAOAAEJkg0sLgAnAAAPAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8uAAIQAAkJmBR2IQC3AQAQAAkJmBR2IQC3AQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAEALgADCgYJCAAAAA==.Angras:BAABLgAECn9HAAIRAAkJcRi2BAAXAgARAAkJcRi2BAAXAgAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgAECgcJBwAAAA==.Anolana:BAABLgAECn8+AAMSAAkJZiL6BADoAgASAAkJZiL6BADoAgATAAEJixEPJwA3AAAAAA==.Anrom:BAAALgAECgEJAQAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn9HAAIUAAkJWRj+AAD9AQAUAAkJWRj+AAD9AQAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Arane:BAAALgAECgkJDAAAAA==.Ariûs:BAABLgAECn8hAAIVAAkJ/BNhBgBPAQAVAAkJ/BNhBgBPAQAAAA==.Arlin:BAABLgAECn8iAAIWAAYJLSP2AQA2AgAWAAYJLSP2AQA2AgAAAA==.Arlorian:BAABLgAECn85AAITAAkJLhWJBQAeAgATAAkJLhWJBQAeAgAAAA==.Arorra:BAAALgAECgYJBgAAAA==.Arrex:BAAALgAECgYJCAAAAA==.Arrowsmites:BAABLgAECn81AAILAAkJaB55HQB0AgALAAkJaB55HQB0AgAAAA==.',
Au='Aubani:BAABLgAECn8zAAMWAAkJnyBlCQD1AgAWAAkJnyBlCQD1AgACAAUJIxII2wDkAAAAAA==.',
Aw='Awishanay:BAAALgADCgQJBAAAAA==.',
Ax='Axelot:BAAALgAECgQJBgAAAA==.',
Ay='Ayperos:BAABLgAECn9cAAMXAAkJ6BvwAABPAgAXAAkJ6BvwAABPAgAVAAYJPxAVUgBhAQAAAA==.Ayvaria:BAEALgAECgYJEwABLgAECgkJKwAYACQXAA==.',
Ba='Baboyago:BAAALgAECggJEQAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Bahemith:BAAALgAECgEJAQAAAA==.Baked:BAAALgAECgQJBAABLgAECgkJNQACAOoJAA==.Bakedpally:BAABLgAECn81AAICAAkJ6gm4GQDbAAACAAkJ6gm4GQDbAAAAAA==.Bandomar:BAABLgAECn8uAAIHAAgJXBBGBQBaAQAHAAgJXBBGBQBaAQAAAA==.Baniemo:BAAALgAECgIJBQAAAA==.Banigor:BAAALgAECgYJEwAAAA==.Basak:BAAALgAECgYJCwABLgAFFAYJHQAEAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Beanjaeden:BAAALgAECgMJAwAAAA==.Beargrillz:BAAALgAECgIJAgAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn81AAICAAkJliEuEgDXAgACAAkJliEuEgDXAgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJDwAAAA==.Belithsong:BAAALgAECgkJBwAAAA==.Bereth:BAABLgAECn8fAAILAAYJKRbYEAA4AQALAAYJKRbYEAA4AQAAAA==.Berreydingle:BAAALgAECgUJEAAAAA==.',
Bi='Bigfuut:BAAALgADCgEJAQAAAA==.Bigkitty:BAABLgAECn8qAAIVAAkJnhlLGgAbAgAVAAkJnhlLGgAbAgAAAA==.Bikinibrenda:BAABLgAFFH8FAAIXAAMJAAeJEACsAAAXAAMJAAeJEACsAAAAAA==.Birchum:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.Biz:BAAALgADCgYJBwABLgAECgkJGwAZAOEhAA==.',
Bl='Blackanvil:BAABLgAECn8aAAIVAAgJ7BAfCwDpAAAVAAgJ7BAfCwDpAAAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECggJHwAVAPcbAA==.Blackhuuf:BAAALgADCgkJDAAAAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodmender:BAAALgAECgIJAgABLgAECgkJLgARADwlAA==.Bloodredsky:BAABLgAECn8nAAMaAAkJABYvBgCzAQAaAAkJABYvBgCzAQAZAAIJ5g2tlQA6AAAAAA==.Bloodsmage:BAAALgAECgMJAwAAAA==.Bloodymagi:BAABLgAECn8sAAIMAAkJhQfJgwBwAQAMAAkJhQfJgwBwAQAAAA==.Bluesummer:BAABLgAECn8fAAQVAAgJ9xsNJQDOAQAVAAcJrR4NJQDOAQAbAAYJxBrAGQCCAQAXAAEJCAzpQQA1AAAAAA==.',
Bo='Bobeh:BAAALgAECgUJCwABLgAECgkJMgACAEIfAA==.Boboh:BAAALgAECgUJBQABLgAECgkJMgACAEIfAA==.Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMIAAkJuhoBCgBIAgAIAAkJuhoBCgBIAgAHAAQJdQbVbQBtAAAAAA==.Borat:BAAALgAECgUJCgABLgAECgkJOAACAFolAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAABLgAECn8bAAIZAAkJ4SH+CQCjAgAZAAkJ4SH+CQCjAgAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECggJDwAAAA==.Bròly:BAAALgAECgEJAgAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIcAAkJIxS3DgCKAQAcAAkJIxS3DgCKAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calquo:BAAALgAECgMJAwABLgAECggJNgASACEgAA==.Calvert:BAAALgAECgUJBgAAAA==.Calytrix:BAEALgAECgMJBAABLgAECgkJKwAYACQXAA==.Captnhammer:BAAALgAECgYJCgAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAABLgAECn8aAAIdAAYJkwUHEACXAAAdAAYJkwUHEACXAAAAAA==.Castration:BAABLgAECn8YAAIdAAYJ3AmOTgDVAAAdAAYJ3AmOTgDVAAAAAA==.Catavitch:BAAALgADCgIJAgAAAA==.',
Ce='Ceylan:BAABLgAECn8zAAMMAAkJ3BppMABXAgAMAAkJ3BppMABXAgAeAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgYJCwAAAA==.Charavane:BAAALgAECgQJBAAAAA==.Charlz:BAABLgAECn8jAAMdAAkJhBZ4HADhAQAdAAkJhBZ4HADhAQAQAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheat:BAAALgAECgYJDgAAAA==.Cheatdr:BAABLgAECn8yAAIBAAkJgQ/6NQDCAQABAAkJgQ/6NQDCAQAAAA==.Cheatpriest:BAACLgAFFH8FAAIQAAMJpQphEQCJAAAQAAMJpQphEQCJAAAuAAQKfz8AAhAACQmbGWkaAPcBABAACQmbGWkaAPcBAAAA.Chepis:BAAALgAECgUJCgAAAA==.Chesthyr:BAAALgAECgQJBQAAAA==.Chesto:BAABLgAECn89AAQfAAkJ7hx7BABVAgAfAAkJZBp7BABVAgAUAAcJ4xplCgCeAQAJAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgAECgIJAgAAAA==.Chimken:BAAALgAECgcJCAABLgAECgkJKQAXADUeAA==.Chokea:BAAALgAECgkJDwAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.Chyrstal:BAAALgAECgEJAQAAAA==.',
Ci='Cindrethresh:BAAALgAECgUJBQAAAA==.',
Co='Cognition:BAACLgAFFH8PAAILAAMJGR9+JQD5AAALAAMJGR9+JQD5AAAuAAQKf3IAAgsACQkcJl0BAIMDAAsACQkcJl0BAIMDAAAA.Coldvengance:BAABLgAECn89AAIVAAkJAQpoNgBuAQAVAAkJAQpoNgBuAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAAEAAAAAA==.Cranknstein:BAAALgAECgIJAgABLgAECgIJBAAEAAAAAA==.Crazycalla:BAABLgAFFH8FAAICAAMJiwdcRgB3AAACAAMJiwdcRgB3AAAAAA==.Critias:BAAALgADCgEJAQAAAA==.Crosbyy:BAAALgAECgUJCgAAAA==.Cruxer:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJAwABLgAECgIJBAAEAAAAAA==.',
Cy='Cymindel:BAABLgAECn9CAAIgAAkJXRzgDAA+AgAgAAkJXRzgDAA+AgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Daithi:BAABLgAECn8UAAIhAAYJXgtJQAAKAQAhAAYJXgtJQAAKAQAAAA==.Dakotà:BAABLgAECn8uAAILAAkJyBtLLwAfAgALAAkJyBtLLwAfAgAAAA==.Darc:BAAALgAECgUJBwAAAA==.Daredayo:BAAALgAECgEJAQAAAA==.Darkangelz:BAAALgAECgIJAgAAAA==.Darkkubo:BAAALgAECgEJAQAAAA==.Darklite:BAAALgADCgYJGAAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Davinci:BAAALgADCgEJAQAAAA==.Day:BAABLgAECn8lAAILAAkJHhkWKwAxAgALAAkJHhkWKwAxAgAAAA==.Dayztocome:BAAALgADCgEJAQAAAA==.',
De='Decaydence:BAABLgAECn8WAAIRAAgJdQl+GADHAAARAAgJdQl+GADHAAAAAA==.Dejno:BAABLgAECn8YAAIVAAcJMiDjLACfAQAVAAcJMiDjLACfAQAAAA==.Deleted:BAAALgAECgEJAQABLgAECgkJLgARADwlAA==.Demonicly:BAABLgAECn8YAAIOAAgJPBLiDgBiAQAOAAgJPBLiDgBiAQAAAA==.Demonred:BAAALgADCggJCAAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgAECgQJBAAAAA==.Dezign:BAACLgAFFH8ZAAIMAAcJMxvOJQDiAQAMAAcJMxvOJQDiAQAuAAQKfykAAgwACQl2IOooAM8CAAwACQl2IOooAM8CAAAA.Dezígn:BAABLgAFFH8IAAIJAAQJAhKeVAAdAQAJAAQJAhKeVAAdAQABLgAFFAcJGQAMADMbAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMiAAYJQQxuUQC9AAAiAAUJvA5uUQC9AAAZAAEJVQIkwAAYAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAFFAMJBgAJABEOAA==.',
Do='Dobbi:BAAALgAFFAEJAQAAAA==.Dolgorukov:BAABLgAECn8xAAILAAkJXhNORQDSAQALAAkJXhNORQDSAQAAAA==.Dologony:BAABLgAECn8jAAIBAAkJmg4sQACRAQABAAkJmg4sQACRAQAAAA==.Dorgar:BAAALgAECgMJAwAAAA==.',
Dr='Dracigor:BAAALgAECgQJBwAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgUJEQAAAA==.Drakhan:BAAALgADCgIJAgAAAA==.Dre:BAAALgAECgMJCAAAAA==.Drensfury:BAAALgAECgIJAgAAAA==.Dreåm:BAAALgADCgQJBAABLgAFFAMJBgAJABEOAA==.Drikken:BAACLgAFFH8GAAMOAAMJjA+DBgB0AAAOAAIJqw6DBgB0AAAPAAIJbgzIOwBpAAAuAAQKf1AABA8ACQnbH70DAOUBAA8ACQluHr0DAOUBAA4ABQnbG+AUAAcBAA0ABQmAFkYwAAYBAAAA.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAINAAkJVxgdGADCAQANAAkJVxgdGADCAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECgkJLgARADwlAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8lAAMcAAcJ9gy7GQAFAQAcAAUJMg67GQAFAQARAAcJWwdpygDwAAAAAA==.Duressa:BAAALgAECgkJCQAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMUAAgJIhX0CQCmAQAUAAgJIhX0CQCmAQAJAAIJZwswDQFbAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAABLgAECn8UAAMWAAgJRRTNAgDpAQAWAAgJRRTNAgDpAQADAAUJywdWOAB9AAAAAA==.Effinfu:BAABLgAECn8pAAIiAAkJ3RKkAwAvAQAiAAkJ3RKkAwAvAQAAAA==.',
Ei='Eitent:BAACLgAFFH8JAAIWAAMJTxphDwDhAAAWAAMJTxphDwDhAAAuAAQKfzAAAxYACQm7HcUNAKoCABYACQm7HcUNAKoCAAIABwm6EhF2AI4BAAEuAAUUAwkKACEAqxMA.Eitentormu:BAAALgAECggJCAABLgAFFAMJCgAhAKsTAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgcJIQAWAN4gAA==.Ellesthara:BAABLgAECn8UAAIBAAcJNwkuEAB3AAABAAcJNwkuEAB3AAAAAA==.Ellysiaa:BAABLgAECn8XAAIGAAYJ3QWeMgCVAAAGAAYJ3QWeMgCVAAAAAA==.Elrïc:BAAALgAECgYJCgAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8zAAMHAAkJwRV+GQAAAgAHAAkJwRV+GQAAAgABAAcJMA0rWAAwAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgAECgEJAQAAAA==.Enyxea:BAABLgAECn8bAAIFAAkJ8ReaKgARAgAFAAkJ8ReaKgARAgAAAA==.',
Ep='Ephemera:BAAALgAECgYJEQAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgAECgIJAwAAAA==.',
Es='Esmeray:BAEBLgAECn8nAAIhAAkJPBdxAgAqAgAhAAkJPBdxAgAqAgABLgAECgkJKwAYACQXAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAABLgAECn8kAAIDAAkJVh8LBADHAgADAAkJVh8LBADHAgAAAA==.Eyewana:BAABLgAECn8kAAINAAkJchKbHQCPAQANAAkJchKbHQCPAQAAAA==.',
Ez='Ezzka:BAACLgAFFH8NAAIRAAMJKSDCKQAcAQARAAMJKSDCKQAcAQAuAAQKfycAAhEACQkJHWkgAIcCABEACQkJHWkgAIcCAAAA.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJDgAAAA==.Fangalor:BAAALgAECgEJBAAAAA==.Farnsworth:BAABLgAECn8eAAQJAAkJ4R0KHwBqAgAJAAgJ+x0KHwBqAgAUAAMJGBxCIQCkAAAfAAEJNBPrOQBBAAAAAA==.Farzix:BAABLgAECn8qAAIKAAkJKQn3PABCAQAKAAkJKQn3PABCAQAAAA==.Façade:BAABLgAECn8mAAIRAAkJDxMYYACpAQARAAkJDxMYYACpAQAAAA==.',
Fe='Feelgood:BAAALgAFFAEJAQAAAA==.Fefifiona:BAACLgAFFH8FAAIhAAIJOA2fQAB3AAAhAAIJOA2fQAB3AAAuAAQKfxkAAiEACQkqF2sQAGoCACEACQkqF2sQAGoCAAAA.Fefifredrich:BAAALgAECgMJAwABLgAFFAIJBQAhADgNAA==.Fefifuredric:BAAALgAECgQJBQABLgAFFAIJBQAhADgNAA==.Felvira:BAABLgAECn8dAAMPAAgJPgTO1ACLAAAPAAYJbQPO1ACLAAANAAUJWwRCWgBZAAAAAA==.',
Fi='Finnw:BAABLgAECn8hAAIWAAcJ3iDmEACPAgAWAAcJ3iDmEACPAgAAAA==.Firelite:BAABLgAECn8oAAIKAAkJYw/9OwBFAQAKAAkJYw/9OwBFAQAAAA==.',
Fl='Flairlock:BAABLgAECn8/AAMfAAkJZyGxAgCfAgAfAAkJZyGxAgCfAgAUAAIJBhW3PAA5AAAAAA==.Flee:BAABLgAECn8iAAISAAkJqRoKDwA7AgASAAkJqRoKDwA7AgAAAA==.Flexo:BAAALgAECgYJBQABLgAECgkJHgAJAOEdAA==.',
Fo='Fookster:BAABLgAECn8ZAAIMAAkJyhPfQAAaAgAMAAkJyhPfQAAaAgAAAA==.Forsetee:BAABLgAFFH8GAAIiAAIJTReHRACQAAAiAAIJTReHRACQAAAAAA==.',
Fr='Frowdawn:BAABLgAECn87AAITAAkJUxCwBwDcAQATAAkJUxCwBwDcAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAAEAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgARACoaAA==.',
Ga='Ga:BAAALgAECgIJAgAAAA==.Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAABLgAECn8iAAIbAAYJzRMgBQAJAQAbAAYJzRMgBQAJAQAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJMAARANYiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.Genericeric:BAAALgADCgQJBAAAAA==.',
Gi='Gilas:BAAALgADCgYJEAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8xAAIBAAkJigzhRgB0AQABAAkJigzhRgB0AQAAAA==.Glizzygoblin:BAAALgAECgEJAQAAAA==.',
Go='Googoobler:BAABLgAECn8mAAINAAgJ7QmqLwAJAQANAAgJ7QmqLwAJAQAAAA==.Goudaluck:BAAALgADCgUJBwABLgAECgkJKgAVAJ4ZAA==.Goudanight:BAAALgAECgMJBQABLgAECgkJKgAVAJ4ZAA==.Goudavibes:BAAALgAECgEJAQABLgAECgkJKgAVAJ4ZAA==.',
Gr='Greenmagus:BAAALgAECgQJBAAAAA==.Grenadon:BAABLgAECn8fAAIIAAYJLga4DQCAAAAIAAYJLga4DQCAAAAAAA==.Gridimbor:BAAALgAECgEJAQAAAA==.Grimlilith:BAABLgAECn8bAAQfAAgJ/wSbEQATAQAfAAgJ9gSbEQATAQAJAAMJBAMCMQE5AAAUAAEJAAAogQALAAAAAA==.Grimmhoof:BAAALgAECgIJAgAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gulem:BAAALgADCgYJBgAAAA==.Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn9AAAIdAAkJOx0NDQCCAgAdAAkJOx0NDQCCAgAAAA==.Hakitua:BAABLgAECn8mAAIOAAkJ2w1pDgBqAQAOAAkJ2w1pDgBqAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDgAAAA==.Hatshepsut:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn9AAAIVAAkJ1A/3KAC2AQAVAAkJ1A/3KAC2AQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAABLgAECn89AAQbAAkJBibGAABpAwAbAAkJBibGAABpAwAVAAkJ1huOHgD6AQAXAAMJvxAeTQCbAAABLgAFFAMJBgAJABEOAA==.Heis:BAABLgAECn8jAAIVAAcJJxlfAwDIAQAVAAcJJxlfAwDIAQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8xAAICAAkJABcwQwD9AQACAAkJABcwQwD9AQAAAA==.',
Hi='Hiko:BAABLgAECn8fAAMiAAgJjhDMBAD6AAAiAAgJjhDMBAD6AAAZAAEJggNDugAfAAAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMFAAYJJgqFAgC9AQAFAAYJJgqFAgC9AQAKAAUJFB/mHQAuAQAuAAQKfyEAAwoACQlzIWYDAG0DAAoACQlzIWYDAG0DAAUABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgAFACYKAA==.Holyangus:BAAALgAECgUJDQAAAA==.Holyfawn:BAAALgADCgEJAQAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.Housemom:BAAALgAECgEJAQAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.Hulahoof:BAAALgAECgcJDgAAAA==.',
Ib='Ibbert:BAAALgAECgEJAQAAAA==.',
Ic='Icculus:BAABLgAECn8sAAILAAgJzxsABQAyAgALAAgJzxsABQAyAgAAAA==.Iceticles:BAAALgAECgYJBQAAAA==.',
Il='Illuyanka:BAAALgAECgIJAgAAAA==.',
Im='Imaresmashy:BAAALgAECgMJAwABLgAECgkJJAAEAAAAAA==.Impasse:BAAALgAECgkJCAAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8+AAIiAAkJaSTgAQBKAwAiAAkJaSTgAQBKAwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgAEAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Iy='Iyrus:BAAALgAECgkJCQAAAA==.',
Ja='Jacolynn:BAABLgAECn8ZAAIaAAcJBRLsKwBXAQAaAAcJBRLsKwBXAQAAAA==.Jaenei:BAAALgAECgcJDwAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Ji='Jinrok:BAAALgAECgUJBgAAAA==.',
Jo='Joansnow:BAAALgAECgcJBwABLgAECgkJJwAaAAAWAA==.Joatmoa:BAACLgAFFH8GAAIGAAMJNRTlDQDbAAAGAAMJNRTlDQDbAAAuAAQKfxQAAgYACQmIHP8PALcBAAYACQmIHP8PALcBAAAA.Joeexotics:BAAALgADCgkJDAAAAA==.Johnlebron:BAAALgAECgEJAwABLgAECgcJDgAEAAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECggJEgAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCggJJgAAAA==.',
Ka='Kaelnis:BAAALgAECggJEgAAAA==.Kaimargonar:BAABLgAECn8eAAIUAAgJkhamCwCFAQAUAAgJkhamCwCFAQAAAA==.Kaitoi:BAABLgAECn8jAAMGAAkJ7BzPBACtAgAGAAkJ7BzPBACtAgAIAAUJKwi0TAB4AAAAAA==.Kalinth:BAAALgADCgIJAgAAAA==.Kallah:BAACLgAFFH8lAAIWAAgJcB8ZCAA/AgAWAAgJcB8ZCAA/AgAuAAQKfzcAAhYACQnsI44BAGsDABYACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn9BAAQjAAkJHBkSCQBZAgAjAAgJjxkSCQBZAgAYAAkJnBGJBwDCAQAkAAEJMRm3FQBDAAAAAA==.Kamakizeg:BAACLgAFFH8FAAICAAIJIQ1SkwCNAAACAAIJIQ1SkwCNAAAuAAQKfy8AAgIACQl3FA1RANUBAAIACQl3FA1RANUBAAAA.Kamayla:BAAALgADCgYJBgAAAA==.Karnus:BAAALgADCgUJBQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAACLgAFFH8GAAIMAAMJCRdQMADsAAAMAAMJCRdQMADsAAAuAAQKfygAAgwACQl2HaQhAJcCAAwACQl2HaQhAJcCAAEuAAUUAwkNABEAKSAA.',
Ke='Kestrelle:BAABLgAECn8ZAAIQAAcJCQpHCQDnAAAQAAcJCQpHCQDnAAABLgAECgkJXAABAPkSAA==.Keyzeus:BAABLgAECn8lAAMYAAgJCxibBgDjAQAYAAgJCxibBgDjAQAkAAEJ5xsAhwBOAAAAAA==.',
Kh='Khas:BAAALgADCgkJHQAAAA==.Khui:BAACLgAFFH8iAAMaAAgJeiQDCgBoAgAaAAgJeiQDCgBoAgAZAAMJDRqoCQDuAAAuAAQKfyUAAxoACAkWJcACAFcDABoACAkWJcACAFcDABkAAwkwGLdSAL4AAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBwAAAA==.Killian:BAAALgAECgYJBgAAAA==.Kipziep:BAAALgAECgIJAgAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8bAAMRAAgJ2xekJQDWAQARAAcJ2xekJQDWAQAgAAEJAAB8VgAAAAAuAAQKfygAAhEACQn9INMSAAsDABEACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8rAAIaAAkJ/RciFgBpAgAaAAkJ/RciFgBpAgABLgAFFAgJGwARANsXAA==.',
Ko='Koltharaz:BAABLgAFFH8IAAIkAAUJqAfiEwADAQAkAAUJqAfiEwADAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAAEAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.Kozatra:BAAALgAECgUJCAAAAA==.',
Kr='Krankthas:BAAALgAECgIJAgABLgAECgIJBAAEAAAAAA==.Krazylock:BAAALgAECgQJCQAAAA==.Krazysniper:BAABLgAECn8oAAMLAAgJCRy0MAAZAgALAAcJEB+0MAAZAgAlAAEJ4wmKYgA3AAAAAA==.Kreepa:BAAALgADCgIJAgAAAA==.Krokk:BAABLgAECn8UAAIKAAcJ9QdiVQDlAAAKAAcJ9QdiVQDlAAAAAA==.Kruulock:BAAALgADCgcJBwAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAFFAEJAQABLgAFFAYJHQAEAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMCAAgJFh66KgB5AgACAAgJFh66KgB5AgAWAAYJOBheOwBbAQAAAA==.Lacosanostra:BAABLgAECn8UAAMZAAYJ2wQQDgB0AAAZAAYJ2wQQDgB0AAAaAAMJkQTTKwA7AAAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lancedragon:BAAALgADCgEJAQAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgACABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8rAAILAAkJjxi2TwCzAQALAAkJjxi2TwCzAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgkJJAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lenard:BAAALgAECgEJAQAAAA==.Lezsul:BAAALgAECgIJAgAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8fAAICAAcJAhIflgBIAQACAAcJAhIflgBIAQAAAA==.Lightguard:BAABLgAECn8XAAMCAAkJoAYcIAC0AAACAAUJJgccIAC0AAADAAYJLgSUDABjAAAAAA==.Lighthouse:BAABLgAECn8wAAICAAkJlxtFNQArAgACAAkJlxtFNQArAgAAAA==.Lileth:BAAALgAECggJCQAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgAECgIJAgAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lolalazer:BAABLgAECn8WAAIPAAgJ9RVJWwB2AQAPAAgJ9RVJWwB2AQAAAA==.Lolhahabaha:BAAALgAECggJDQAAAA==.Loopie:BAAALgADCgYJCgAAAA==.Loranthyr:BAAALgADCgQJBAAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8fAAIgAAgJURQqBQAvAQAgAAgJURQqBQAvAQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgkJHwALAPgfAA==.',
Ly='Lypally:BAABLgAECn9OAAICAAkJrRsiBABYAgACAAkJrRsiBABYAgAAAA==.',
['Là']='Làdedá:BAAALgAECgYJCgAAAA==.',
['Lï']='Lïllïth:BAAALgAECgkJEAAAAA==.Lïly:BAAALgADCggJEAABLgAECgkJJAAEAAAAAA==.',
['Ló']='Lóla:BAABLgAECn8wAAIPAAkJziMYCAAPAwAPAAkJziMYCAAPAwAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8oAAMSAAgJGRaLBQBkAgASAAgJGRaLBQBkAgATAAYJOw8xAwBvAQAuAAQKfyEAAxIACAlGHtkMAMsCABIACAlGHtkMAMsCABMAAQnoGt8aAFEAAAAA.Magegrizz:BAAALgAECgcJCQAAAA==.Mahimahi:BAAALgAECggJCAAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8fAAImAAkJphVTCgAUAgAmAAkJphVTCgAUAgAAAA==.Mariacuras:BAABLgAECn8WAAIWAAkJ7AqDMQCRAQAWAAkJ7AqDMQCRAQAAAA==.Marle:BAABLgAECn87AAIPAAkJ1RifAwDrAQAPAAkJ1RifAwDrAQAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgAECgUJBwAAAA==.Martis:BAAALgAFFAEJAQAAAA==.Marynne:BAABLgAECn9cAAMBAAkJ+RKcBQBtAQABAAkJ+RKcBQBtAQAHAAEJSwKerAAMAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8zAAMOAAkJvxc0BwASAgAOAAkJUBc0BwASAgANAAIJ7xmDDQCNAAAAAA==.',
Mc='Mcdo:BAAALgAFFAIJAgABLgAFFAgJGgAnACYbAA==.Mctank:BAAALgAECgEJAQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgAECgUJBQAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8wAAMdAAgJhQ8nKgCAAQAdAAgJhQ8nKgCAAQAQAAUJxQwWTgCqAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAABLgAECn8tAAQCAAcJ4hpVBwDPAQACAAcJ4hpVBwDPAQAWAAYJ6A+QDgB0AAADAAIJRg3SDgBRAAABLgAECgkJLAANAGcfAA==.Meliza:BAAALgAECgEJAQABLgAECgYJCgAEAAAAAA==.Merrikeath:BAABLgAECn8cAAIRAAkJPgh2FADlAAARAAkJPgh2FADlAAAAAA==.Merriklade:BAABLgAECn8zAAMbAAkJAA8oFwCKAQAbAAkJRw4oFwCKAQAVAAgJzQozOwBZAQAAAA==.Merrikoid:BAAALgAECgUJCAAAAA==.Merrikwolf:BAAALgAECgYJDgAAAA==.',
Mi='Misamina:BAAALgAECgMJAwAAAA==.Missyjelliot:BAAALgAECggJDwAAAA==.',
Mo='Monster:BAAALgADCgEJAQAAAA==.Moof:BAAALgADCgEJAQAAAA==.Morbidstyle:BAAALgAECgYJCgABLgAFFAYJGgALAOAVAA==.Morchuk:BAAALgADCgMJAwAAAA==.Morigith:BAAALgAECgQJBwABLgAECgYJCgAEAAAAAA==.Morthos:BAAALgAECgUJCAAAAA==.Mousé:BAAALgAECgEJAwAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgcJIQAWAN4gAA==.',
My='Myora:BAEBLgAECn8nAAISAAkJvx6pAADfAgASAAkJvx6pAADfAgABLgAECgkJKwAYACQXAA==.Mythundirus:BAAALgADCgMJAwAAAA==.',
['Mà']='Màrli:BAABLgAECn8YAAMgAAkJbBG5AwB+AQAgAAkJbBG5AwB+AQAcAAcJ8QiDGgD8AAAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8iAAIDAAkJQRPcEQCoAQADAAkJQRPcEQCoAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQAXADUeAA==.Nakasid:BAACLgAFFH8KAAIQAAMJYxEBIgCqAAAQAAMJYxEBIgCqAAAuAAQKfz4ABBAACQl5GXECABICABAACQl5GXECABICAB0ABwkVCNQ5ACIBACEABAlbCntcAI0AAAAA.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Naura:BAAALgADCgMJAwAAAA==.Navane:BAAALgAECgUJBwAAAA==.',
Ne='Necromaniac:BAAALgAECgEJAQAAAA==.Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8rAAIPAAkJsBDpQwC8AQAPAAkJsBDpQwC8AQAAAA==.Nevaehstar:BAACLgAFFH8GAAIeAAMJexEEAgDEAAAeAAMJexEEAgDEAAAuAAQKf0sAAh4ACQnzJCIAAPoCAB4ACQnzJCIAAPoCAAAA.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJDQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8wAAIQAAkJOxQKIADDAQAQAAkJOxQKIADDAQAAAA==.Nik:BAAALgADCgcJBgAAAA==.Nikolia:BAABLgAECn8UAAMbAAcJgQ3OBwCuAAAbAAUJgA/OBwCuAAAVAAUJzgZRFgBqAAAAAA==.Ninetynine:BAAALgADCgMJBQAAAA==.Nini:BAABLgAECn8nAAIHAAgJvgKcXQCgAAAHAAgJvgKcXQCgAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJEAANANcSAA==.Nokru:BAAALgADCgMJBQAAAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgAECggJCAAAAA==.',
Nz='Nzuul:BAABLgAECn8YAAIPAAUJfgbWHAB7AAAPAAUJfgbWHAB7AAAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAwAAAA==.',
Om='Ominous:BAAALgAECgMJAwAAAA==.',
On='Onram:BAAALgAECgEJAQAAAA==.',
Op='Oppaissiah:BAABLgAECn9EAAMbAAkJ6iNPAgAlAwAbAAkJlSNPAgAlAwAVAAkJ8R/7CQDDAgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAIkAAYJawJudgB5AAAkAAYJawJudgB5AAABLgAECgkJEgAEAAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.Orman:BAAALgAFFAIJAgAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAABLgAECgkJNQACANcKAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJDAAAAA==.Padrizul:BAAALgADCgEJAQAAAA==.Pandamared:BAAALgADCggJCgAAAA==.Papasbich:BAABLgAECn8lAAINAAcJawm1CQDNAAANAAcJawm1CQDNAAABLgAFFAMJCgACAG0FAA==.Papasfury:BAAALgAECgkJAQABLgAFFAMJCgACAG0FAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Ph='Phantazm:BAAALgADCgEJAQAAAA==.Phenol:BAAALgADCgUJBQAAAA==.Phoxie:BAAALgAECgEJAQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Polog:BAAALgAECgMJAwAAAA==.Porkchoplust:BAAALgAECgEJAgAAAA==.Porkchopw:BAAALgAECgcJAgAAAA==.Porkribs:BAABLgAFFH8HAAIWAAMJ2RZeEADSAAAWAAMJ2RZeEADSAAAAAA==.',
Pr='Presap:BAABLgAECn8zAAMBAAkJBCJuBQBhAwABAAkJBCJuBQBhAwAHAAEJAACrdgBJAAABLgAECgkJGQAjAKwcAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAABLgAECn8iAAIGAAYJNxqyAgBqAQAGAAYJNxqyAgBqAQAAAA==.Pumdmuc:BAACLgAFFH8RAAIQAAUJWRpTEQBEAQAQAAUJWRpTEQBEAQAuAAQKf0oAAxAACQnlIdoGAN8CABAACQnlIdoGAN8CAB0ABwkqBbVTAMMAAAAA.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJEAAAAA==.',
Qu='Quikglaives:BAAALgAFFAMJBAAAAA==.Quille:BAABLgAECn8gAAILAAgJSiPzDgDZAgALAAgJSiPzDgDZAgAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIDAAkJrRJqEQCuAQADAAkJrRJqEQCuAQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgMJBAAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJDAAAAA==.Redrek:BAAALgADCggJLAAAAA==.Redsbank:BAAALgADCgMJBgAAAA==.Redshunter:BAAALgADCgcJFQAAAA==.Redsknight:BAAALgADCgkJDAAAAA==.Redsmonk:BAAALgADCgcJFQAAAA==.Redwinter:BAAALgAECgIJBAABLgAECggJHwAVAPcbAA==.Reikisong:BAAALgAECggJDQAAAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reylia:BAAALgAECgQJBAAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhagurion:BAAALgAFFAEJAQAAAA==.Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8tAAMBAAgJbBduAwDrAQABAAgJbBduAwDrAQAHAAEJiglUHgAmAAAAAA==.',
Ro='Rockmonsta:BAAALgAECgUJCgAAAA==.Rockrat:BAAALgADCgEJAQAAAA==.Rodeo:BAABLgAECn8sAAIHAAkJABCiIwCtAQAHAAkJABCiIwCtAQAAAA==.Rotgutwiskey:BAAALgAECgIJAgAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.Royan:BAABLgAECn8VAAIQAAkJ6Q/6AwCqAQAQAAkJ6Q/6AwCqAQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAIPAAYJeQ6eegA4AQAPAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAECgcJCgAAAA==.Sadnhornless:BAAALgAECgEJAwAAAA==.Saeti:BAACLgAFFH8XAAMGAAQJex7ICQARAQAGAAMJfiDICQARAQAHAAEJbxiNSQBMAAAuAAQKfz8ABQYACQlIIZYHAG8CAAYACQlAIZYHAG8CAAcABgkKHTIrAHwBAAgABAk2HlIrAAQBAAEABAkUFoqIAKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sanh:BAAALgAECgEJAQAAAA==.Sapplesauce:BAABLgAECn8XAAISAAgJ5Bc9HgCkAQASAAgJ5Bc9HgCkAQAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Sedael:BAAALgAECgIJAgABLgAECgYJIgAWAC0jAA==.Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAACLgAFFH8MAAMBAAMJQgnZHAB6AAABAAMJQgnZHAB6AAAHAAEJ4wYnUQA0AAAuAAQKf1gAAwEACQkwH/ALAAEDAAEACQkwH/ALAAEDAAcABgmbE5Y4ADEBAAAA.',
Sh='Shadý:BAABLgAECn8vAAILAAkJ5AoTVgCiAQALAAkJ5AoTVgCiAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECgkJLgARADwlAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQUAAgJLBqNCwCIAQAJAAgJ1hcKRADPAQAUAAcJeBiNCwCIAQAfAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn9IAAIVAAkJohxfDgCLAgAVAAkJohxfDgCLAgAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sianu:BAAALgAECgcJDgABLgAECgkJXAABAPkSAA==.Sidarya:BAABLgAECn8ZAAMQAAgJgRcDGgD7AQAQAAgJgRcDGgD7AQAdAAIJZgcnIgAoAAAAAA==.Sidera:BAAALgAECggJDgAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Sidusa:BAAALgADCgcJBwAAAA==.Silent:BAACLgAFFH8bAAMVAAQJxB5mDQAhAQAVAAQJxB5mDQAhAQAXAAEJPAxiQgBDAAAuAAQKfx4AAxcACQmjFs4ZACUBABUABwlxFW5EADQBABcABgkoEs4ZACUBAAAA.Silveric:BAAALgADCgYJCQAAAA==.Silverserket:BAAALgAECgIJBAAAAA==.Silverserqet:BAABLgAECn8WAAILAAcJgA5LhAA2AQALAAcJgA5LhAA2AQAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn9SAAMFAAkJQBadBQDZAQAFAAkJQBadBQDZAQAKAAgJQAiaSgAKAQAAAA==.Skyscales:BAEALgAECgcJBwABLgAECgkJUgAFAEAWAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.Slipknaught:BAAALgAECgQJAwABLgAECgkJJwAaAAAWAA==.',
Sm='Smileyriley:BAABLgAECn8bAAIHAAcJcgbfTwDOAAAHAAcJcgbfTwDOAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBQABLgAECgcJDgAEAAAAAA==.Snot:BAAALgADCgEJAQAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.Snèakyboots:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAABLgAECn8XAAIaAAUJCwRzlQBtAAAaAAUJCwRzlQBtAAAAAA==.Solarêclipse:BAAALgAECgUJBgAAAA==.Sooki:BAAALgAECgIJBAAAAA==.Sorath:BAAALgAECgMJAwAAAA==.Sorilea:BAAALgADCgkJGQAAAA==.Sorlis:BAAALgAECgcJEwAAAA==.Soulber:BAABLgAECn8bAAMRAAkJwRTjWAC7AQARAAkJ5RPjWAC7AQAgAAIJnxxUPACgAAAAAA==.Sourdew:BAABLgAECn8eAAIZAAcJtB7ZGQDiAQAZAAcJtB7ZGQDiAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8ZAAMjAAkJrBwjBADzAgAjAAkJrBwjBADzAgAYAAEJAAA/LwAAAAAAAA==.Splashgordon:BAAALgAECgQJBAABLgAECgkJGQAjAKwcAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwAEAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgUJCwAAAA==.Stefeana:BAAALgAECgYJBgAAAA==.Stelle:BAABLgAECn8XAAIhAAgJBBEYJABzAQAhAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgIJAgAAAA==.Stylos:BAABLgAECn9BAAImAAgJPBclDADwAQAmAAgJPBclDADwAQAAAA==.Stãrburst:BAABLgAECn8UAAMFAAgJZQr4ewDsAAAFAAcJswf4ewDsAAAKAAEJUASqvwAeAAAAAA==.',
Su='Subrinea:BAAALgAECgUJBQABLgAFFAMJBgAeAHsRAA==.Sumofwhy:BAAALgAECgMJAwAAAA==.',
Sw='Swowtitbang:BAAALgAECgYJBgAAAA==.',
Sy='Sylven:BAAALgADCgYJBgABLgAFFAMJBgAJABEOAA==.',
Ta='Taissa:BAAALgADCggJCwAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECggJEwAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQgAAgJNBm8EwDXAQAgAAgJVBi8EwDXAQARAAgJBQ8oZwDAAQAcAAEJAACfGgAeAAABLgAECgkJDgAEAAAAAA==.Tegmage:BAAALgAECgUJBQABLgAECgkJDgAEAAAAAA==.Tempestrike:BAAALgAFFAIJAwAAAA==.Terentia:BAEALgAECgUJBQABLgAECgkJKwAYACQXAA==.',
Th='Thadind:BAAALgAECgQJBAAAAA==.Thalodrim:BAAALgAECgEJAQABLgAECgkJHgAJAOEdAA==.Tharelly:BAABLgAECn8XAAIMAAkJrxi6OwArAgAMAAkJrxi6OwArAgAAAA==.Thasserian:BAAALgADCgIJAgABLgAFFAMJBgAJABEOAA==.Theholymatt:BAACLgAFFH8XAAMWAAcJqxZBFgB2AQAWAAUJAxRBFgB2AQACAAUJBRZiGwAPAQAuAAQKf0oAAwIACQlVJUcIACkDAAIACQlVJUcIACkDABYABwnnJEEPAJsCAAAA.Thendari:BAABLgAECn+LAAIUAAkJCRqrAABCAgAUAAkJCRqrAABCAgAAAA==.Theodus:BAABLgAECn81AAIMAAkJhxlIOAA3AgAMAAkJhxlIOAA3AgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAIkAAgJfxorHAD0AQAkAAgJfxorHAD0AQABLgAFFAcJFwAWAKsWAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn9PAAMXAAkJYiSUAgAfAwAXAAkJJSSUAgAfAwAVAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8WAAMWAAUJ4hraEQClAQAWAAUJ4hraEQClAQACAAMJpwMiPQCSAAAuAAQKfz0AAhYACQn3IDgFAEADABYACQn3IDgFAEADAAAA.Tislam:BAABLgAECn8bAAIJAAkJag6zaABrAQAJAAkJag6zaABrAQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQXAAkJNR7NBACaAgAXAAkJFhrNBACaAgAbAAcJpSCYDwDuAQAVAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn9RAAIQAAkJMR0vAQCyAgAQAAkJMR0vAQCyAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIbAAkJJBMGFACvAQAbAAkJJBMGFACvAQABLgAECgQJBAAEAAAAAA==.Torolf:BAAALgAECggJEAAAAA==.Torsen:BAAALgADCgcJCAAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgQJBAAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8gAAMKAAgJ5BRyCAAsAgAKAAgJ5BRyCAAsAgAFAAEJYAwCegBLAAAuAAQKf0gAAgoACQnMIswEABQDAAoACQnMIswEABQDAAAA.',
Ts='Tsonokwabain:BAABLgAECn8rAAQcAAkJhyKlAQAYAwAcAAkJhyKlAQAYAwAgAAEJah2JVABIAAARAAEJmALGpgEYAAAAAA==.Tsunami:BAAALgADCgYJCAAAAA==.',
Tu='Tumnus:BAAALgADCgMJBAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tye:BAAALgAFFAEJAgAAAA==.Tyranastrasz:BAABLgAECn8+AAQjAAkJjhfQAQCTAQAjAAkJjhfQAQCTAQAYAAEJ6gYPKQAqAAAkAAEJWQQsGwAgAAAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAISAAkJ4QXSKABRAQASAAkJ4QXSKABRAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAABLgAFFH8FAAIRAAIJPhUAcwBeAAARAAIJPhUAcwBeAAAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAIPAAgJOxgFTgCcAQAPAAgJOxgFTgCcAQAAAA==.Vaerryn:BAABLgAECn8mAAQcAAgJMyOABgA8AgAcAAcJFiOABgA8AgARAAMJcBv80gDkAAAgAAIJQyCDUQBPAAAAAA==.Vaethund:BAAALgAECgkJEwAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAAOAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Valkz:BAAALgADCgEJAQAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vaneesha:BAAALgADCgMJBgAAAA==.Vanesah:BAAALgAECgQJBgAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAABLgAECn8bAAMlAAkJ5ww1KABeAQAlAAcJxQw1KABeAQALAAgJ1wo/MwBgAAAAAA==.Vassyra:BAEBLgAECn8rAAIYAAkJJBdOBQAOAgAYAAkJJBdOBQAOAgAAAA==.',
Ve='Velara:BAAALgAECgcJDAAAAA==.Velesyn:BAABLgAECn8cAAMOAAgJUx9UBwAOAgAOAAcJKCBUBwAOAgAPAAIJtxH7/QBOAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.Venekor:BAAALgADCgUJBQAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.Vitoria:BAAALgAECgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAACLgAFFH8KAAIhAAMJqxMuGQCpAAAhAAMJqxMuGQCpAAAuAAQKfygAAyEACQlbGWgMAKcCACEACQlbGWgMAKcCAB0ACAnVFwYaAPUBAAAA.Volundr:BAABLgAECn9AAAIbAAkJ7xgNDgAKAgAbAAkJ7xgNDgAKAgAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECgkJGwAZAOEhAA==.',
Vy='Vynel:BAAALgAECgYJCQABLgAFFAMJBgAJABEOAA==.Vynirion:BAABLgAECn8UAAIMAAcJqxJUpACPAQAMAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAABLgAECn8iAAISAAkJPQfDBAA1AQASAAkJPQfDBAA1AQAAAA==.Wardellmo:BAAALgAECgEJAQAAAA==.Wargtar:BAABLgAECn82AAISAAgJISD8DQBIAgASAAgJISD8DQBIAgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8bAAMQAAcJ4BKKNgAmAQAQAAcJ4BKKNgAmAQAhAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJDwAAAA==.',
Wh='Whatcow:BAAALgAFFAEJAQAAAA==.Whiteback:BAAALgADCgUJBQAAAA==.Whiterrina:BAAALgADCgkJCgAAAA==.',
Wi='Window:BAAALgAECgEJAQAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8iAAMHAAkJ9AjhMgBPAQAHAAkJ9AjhMgBPAQABAAUJEgfQiwCfAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAILAAkJywobVgBmAQALAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn83AAMFAAkJDSMoDQDuAgAFAAkJDSMoDQDuAgAKAAcJyRiaKACqAQAAAA==.',
Xk='Xkwizet:BAABLgAECn8aAAIMAAgJPgcsoQA5AQAMAAgJPgcsoQA5AQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgAECgEJAQAAAA==.',
Ye='Yet:BAABLgAECn84AAMCAAkJWiVTBQBKAwACAAkJWiVTBQBKAwAWAAUJ/xszBACWAQAAAA==.',
Yi='Yiffweaver:BAABLgAECn80AAIiAAkJKAzbAgBmAQAiAAkJKAzbAgBmAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn80AAIDAAkJfhNXEAC/AQADAAkJfhNXEAC/AQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAABLgAECn8jAAIHAAkJ0AktCQDqAAAHAAkJ0AktCQDqAAAAAA==.',
Za='Zarhianna:BAABLgAECn8jAAIHAAkJgBBHIgC3AQAHAAkJgBBHIgC3AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.Zephnor:BAAALgAECgkJEAAAAA==.',
Zm='Zmona:BAABLgAECn8xAAICAAkJHg+aZwCgAQACAAkJHg+aZwCgAQAAAA==.',
Zo='Zorsche:BAAALgAECgQJBwAAAA==.',
Zu='Zulrok:BAABLgAECn8vAAIVAAkJUR7wEgBbAgAVAAkJUR7wEgBbAgAAAA==.',
['Åv']='Åviendha:BAAALgADCgkJGQAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAIMAAcJ0hZswwBfAQAMAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAABLgAECn8VAAICAAYJ6wNdDgGnAAACAAYJ6wNdDgGnAAAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8uAAIMAAkJUiPnFADcAgAMAAkJUiPnFADcAgAAAA==.',
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
