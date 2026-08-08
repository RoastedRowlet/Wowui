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

local lookup = {'Druid-Restoration','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Warrior-Arms','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Warlock-Affliction','Priest-Discipline','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abrácadabra:BAAALgAECgMJAwABLgAECgkJPwABAOgVAA==.',
Ac='Achilles:BAABLgAFFH8IAAMCAAUJRgx+JwDtAAACAAUJCQt+JwDtAAADAAEJSgjxEwAcAAAAAA==.',
Ad='Aderan:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAAEAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJMwAFAAYhAA==.Aesalon:BAABLgAECn80AAQGAAkJ1CMHBADHAgAGAAkJ1CMHBADHAgAHAAIJrRTjeQA+AAAIAAIJGBMIcwA0AAABLgAECgkJHgAJAOEdAA==.',
Ah='Ahsokatano:BAABLgAECn8zAAMFAAkJBiFuBwA5AwAFAAkJBiFuBwA5AwAKAAEJ8gwQswAnAAAAAA==.',
Ai='Aimspet:BAABLgAECn8XAAIFAAYJFBSKXwA+AQAFAAYJFBSKXwA+AQAAAA==.Aircanada:BAAALgAECgIJBAAAAA==.',
Ak='Akela:BAABLgAECn8oAAILAAkJIQ1sTQC6AQALAAkJIQ1sTQC6AQAAAA==.Akos:BAAALgAECgQJBAABLgAFFAMJDAABAEIJAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAABLgAECn8YAAICAAcJBxSKFQAjAQACAAcJBxSKFQAjAQAAAA==.Amonet:BAABLgAECn8hAAIMAAYJJw+ZGwD2AAAMAAYJJw+ZGwD2AAAAAA==.',
An='Anaelcheese:BAABLgAECn8cAAQNAAcJ1xoPIwBfAQANAAcJ1xoPIwBfAQAOAAEJkg0sLgAnAAAPAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8uAAIQAAkJmBR2IQC3AQAQAAkJmBR2IQC3AQAAAA==.Anaïs:BAAALgAECgQJBAAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAEALgADCgYJCAAAAA==.Angras:BAABLgAECn9MAAMRAAkJLhq7BQAYAgARAAkJkBi7BQAYAgASAAIJIR1jCwCqAAAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgAECgcJBwAAAA==.Anolana:BAABLgAECn8+AAMTAAkJZiL6BADoAgATAAkJZiL6BADoAgAUAAEJixEPJwA3AAAAAA==.Anrom:BAAALgAECgEJAQAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn9HAAIVAAkJWRhOAQABAgAVAAkJWRhOAQABAgAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Arane:BAAALgAECgkJDAAAAA==.Ariûs:BAABLgAECn8hAAIWAAkJ/BPwBwBPAQAWAAkJ/BPwBwBPAQAAAA==.Arlin:BAABLgAECn8pAAIXAAYJqyNhAgBFAgAXAAYJqyNhAgBFAgAAAA==.Arlorian:BAABLgAECn85AAIUAAkJLhWJBQAeAgAUAAkJLhWJBQAeAgAAAA==.Arorra:BAAALgAECgYJBgAAAA==.Arrex:BAAALgAECgYJCAAAAA==.Arrowsmites:BAABLgAECn81AAILAAkJaB55HQB0AgALAAkJaB55HQB0AgAAAA==.',
Au='Aubani:BAABLgAECn8zAAMXAAkJnyBlCQD1AgAXAAkJnyBlCQD1AgACAAUJIxII2wDkAAAAAA==.',
Aw='Awishanay:BAAALgADCgQJBAAAAA==.',
Ax='Axelot:BAAALgAECgQJBgAAAA==.',
Ay='Ayperos:BAABLgAECn9cAAMYAAkJ6BsdAQBcAgAYAAkJ6BsdAQBcAgAWAAYJPxAVUgBhAQAAAA==.Ayvaria:BAEALgAECgYJEwABLgAECgkJJwATAL8eAA==.',
Ba='Baboyago:BAAALgAECggJEQAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Bahemith:BAAALgAECgEJAQAAAA==.Baked:BAAALgAECgQJBAABLgAECgkJPAACAAgNAA==.Bakedpally:BAABLgAECn88AAICAAkJCA16FQAkAQACAAkJCA16FQAkAQAAAA==.Bandomar:BAABLgAECn8uAAIHAAgJXBADBwBXAQAHAAgJXBADBwBXAQAAAA==.Baniemo:BAAALgAECgIJBQAAAA==.Banigor:BAAALgAECgYJEwAAAA==.Basak:BAAALgAECgYJCwABLgAFFAYJHgAEAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Beanjaeden:BAAALgAECgMJAwAAAA==.Beargrillz:BAAALgAECgIJAgAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn81AAICAAkJliEuEgDXAgACAAkJliEuEgDXAgAAAA==.Beckett:BAAALgAECgYJBgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJDwAAAA==.Belithsong:BAAALgAECgkJBwAAAA==.Bereth:BAABLgAECn8jAAILAAYJ7hg5EQBXAQALAAYJ7hg5EQBXAQAAAA==.Berreydingle:BAAALgAECgUJEAAAAA==.',
Bi='Bigfuut:BAAALgADCgEJAQAAAA==.Bigkitty:BAABLgAECn8qAAIWAAkJnhlLGgAbAgAWAAkJnhlLGgAbAgABLgAECgkJOAALAKoiAA==.Bikinibrenda:BAABLgAFFH8HAAMYAAMJAAfoEwCnAAAYAAMJAAfoEwCnAAAWAAEJtASuOgA3AAAAAA==.Birchum:BAAALgADCgkJEAABLgAECgYJCgAEAAAAAA==.Biz:BAAALgADCgYJBwABLgAECgkJGwAZAOEhAA==.',
Bl='Blackanvil:BAABLgAECn8aAAIWAAgJ7BC6MQCFAQAWAAgJ7BC6MQCFAQAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECggJHwAWAPcbAA==.Blackhuuf:BAAALgADCgkJDAAAAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodmender:BAAALgAECgIJAgABLgAECgkJLgARADwlAA==.Bloodredsky:BAABLgAECn8nAAMaAAkJABa1BwCwAQAaAAkJABa1BwCwAQAZAAIJ5g2tlQA6AAAAAA==.Bloodsmage:BAAALgAECgMJAwAAAA==.Bloodymagi:BAABLgAECn8sAAIMAAkJhQfJgwBwAQAMAAkJhQfJgwBwAQAAAA==.Bluesummer:BAABLgAECn8fAAQWAAgJ9xsNJQDOAQAWAAcJrR4NJQDOAQAbAAYJxBrAGQCCAQAYAAEJCAzpQQA1AAAAAA==.',
Bo='Bobeh:BAAALgAECgUJDAABLgAECgkJMgACAEIfAA==.Boboh:BAAALgAECgUJBQABLgAECgkJMgACAEIfAA==.Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMIAAkJuhoBCgBIAgAIAAkJuhoBCgBIAgAHAAQJdQbVbQBtAAAAAA==.Borat:BAAALgAECgUJCgABLgAECgkJOQACAFolAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAABLgAECn8bAAIZAAkJ4SH+CQCjAgAZAAkJ4SH+CQCjAgAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECggJDwAAAA==.Bròly:BAAALgAECgEJAgAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIcAAkJIxS3DgCKAQAcAAkJIxS3DgCKAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calquo:BAAALgAECgMJAwABLgAECggJOAATAJQhAA==.Calvert:BAAALgAECgUJBgAAAA==.Calytrix:BAEALgAECgcJCwABLgAECgkJJwATAL8eAA==.Captnhammer:BAAALgAECgYJCgAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carmelicious:BAAALgAECgEJAQAAAA==.Carnelian:BAABLgAECn8dAAIdAAYJ/QenEgChAAAdAAYJ/QenEgChAAAAAA==.Castration:BAABLgAECn8YAAIdAAYJ3AmOTgDVAAAdAAYJ3AmOTgDVAAAAAA==.Catavitch:BAAALgADCgIJAgAAAA==.',
Ce='Ceylan:BAABLgAECn8zAAMMAAkJ3BppMABXAgAMAAkJ3BppMABXAgAeAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgYJCwAAAA==.Charavane:BAAALgAECgQJBAAAAA==.Charlz:BAABLgAECn8jAAMdAAkJhBZ4HADhAQAdAAkJhBZ4HADhAQAQAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheat:BAAALgAECgYJDgAAAA==.Cheatdr:BAABLgAECn8yAAIBAAkJgQ/6NQDCAQABAAkJgQ/6NQDCAQAAAA==.Cheatpriest:BAACLgAFFH8FAAIQAAMJpQrwEwB8AAAQAAMJpQrwEwB8AAAuAAQKfz8AAhAACQmbGWkaAPcBABAACQmbGWkaAPcBAAAA.Chepis:BAAALgAECgYJDQAAAA==.Chesthyr:BAAALgAECgYJCwAAAA==.Chesto:BAABLgAECn89AAQfAAkJ7hx7BABVAgAfAAkJZBp7BABVAgAVAAcJ4xplCgCeAQAJAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgAECgIJAgAAAA==.Chimken:BAAALgAECgcJCAABLgAECgkJKQAYADUeAA==.Chokea:BAAALgAECgkJDwAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.Chyrstal:BAAALgAECgEJAQAAAA==.',
Ci='Cindrethresh:BAAALgAECgUJBQAAAA==.',
Co='Cognition:BAACLgAFFH8PAAILAAMJGR+CKwDxAAALAAMJGR+CKwDxAAAuAAQKf3IAAgsACQkcJl0BAIMDAAsACQkcJl0BAIMDAAAA.Coldvengance:BAABLgAECn9BAAIWAAkJKArGDAD0AAAWAAkJKArGDAD0AAAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAAEAAAAAA==.Cranknstein:BAAALgAECgIJAgABLgAECgIJBAAEAAAAAA==.Crazycalla:BAABLgAFFH8FAAICAAMJiwdjTgB3AAACAAMJiwdjTgB3AAAAAA==.Critias:BAAALgADCgEJAQAAAA==.Crosbyy:BAAALgAECgUJCgAAAA==.Cruxer:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJAwABLgAECgIJBAAEAAAAAA==.',
Cy='Cymindel:BAABLgAECn9CAAISAAkJXRzgDAA+AgASAAkJXRzgDAA+AgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Daithi:BAABLgAECn8UAAIgAAYJXgtJQAAKAQAgAAYJXgtJQAAKAQAAAA==.Dakotà:BAABLgAECn8uAAILAAkJyBtLLwAfAgALAAkJyBtLLwAfAgAAAA==.Darc:BAAALgAECgYJCAAAAA==.Daredayo:BAAALgAECgEJAQAAAA==.Darkangelz:BAAALgAECgIJAgAAAA==.Darkkubo:BAAALgAECgEJAQAAAA==.Darklite:BAAALgADCgYJGAAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Davinci:BAAALgADCgEJAQAAAA==.Day:BAABLgAECn8lAAILAAkJHhkWKwAxAgALAAkJHhkWKwAxAgAAAA==.Dayztocome:BAAALgADCgEJAQAAAA==.',
De='Decaydence:BAABLgAECn8WAAIRAAgJdQkLHgDBAAARAAgJdQkLHgDBAAAAAA==.Dejno:BAABLgAECn8YAAIWAAcJMiDjLACfAQAWAAcJMiDjLACfAQAAAA==.Deleted:BAAALgAECgEJAQABLgAECgkJLgARADwlAA==.Demonicly:BAABLgAECn8YAAIOAAgJPBLiDgBiAQAOAAgJPBLiDgBiAQAAAA==.Demonred:BAAALgADCggJCAAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgAECgYJDwAAAA==.Dezign:BAACLgAFFH8aAAIMAAgJfxjOJQDiAQAMAAgJfxjOJQDiAQAuAAQKfykAAgwACQl2IOooAM8CAAwACQl2IOooAM8CAAAA.Dezígn:BAABLgAFFH8IAAIJAAQJAhKeVAAdAQAJAAQJAhKeVAAdAQABLgAFFAgJGgAMAH8YAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMhAAYJQQxuUQC9AAAhAAUJvA5uUQC9AAAZAAEJVQIkwAAYAAAAAA==.Divinitÿ:BAAALgAECgEJAQABLgAFFAUJBQAWAIYRAA==.',
Do='Dobbi:BAAALgAFFAEJAQAAAA==.Dolgorukov:BAABLgAECn8xAAILAAkJXhNORQDSAQALAAkJXhNORQDSAQAAAA==.Dologony:BAABLgAECn8jAAIBAAkJmg4sQACRAQABAAkJmg4sQACRAQAAAA==.Dorgar:BAAALgAECgMJAwAAAA==.',
Dr='Dracigor:BAAALgAECgQJBwAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgUJEQAAAA==.Drakhan:BAAALgADCgIJAgAAAA==.Dre:BAAALgAECgMJCAAAAA==.Drensfury:BAAALgAECgIJAgAAAA==.Dreåm:BAAALgADCgQJBAABLgAFFAUJBQAWAIYRAA==.Drikken:BAACLgAFFH8GAAMOAAMJjA+nBwBwAAAOAAIJqw6nBwBwAAAPAAIJbgwaQgBlAAAuAAQKf1AABA8ACQnbH88EAN8BAA8ACQluHs8EAN8BAA4ABQnbG+AUAAcBAA0ABQmAFkYwAAYBAAAA.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAINAAkJVxgdGADCAQANAAkJVxgdGADCAQAAAA==.Druiddeleted:BAAALgAECgEJBQABLgAECgkJLgARADwlAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8lAAMcAAcJ9gy7GQAFAQAcAAUJMg67GQAFAQARAAcJWwdpygDwAAAAAA==.Duressa:BAAALgAECgkJCQAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMVAAgJIhX0CQCmAQAVAAgJIhX0CQCmAQAJAAIJZwswDQFbAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAABLgAECn8UAAMXAAgJRRSNAwDtAQAXAAgJRRSNAwDtAQADAAUJywdWOAB9AAAAAA==.Effinfu:BAABLgAECn8pAAIhAAkJ3RJnBAApAQAhAAkJ3RJnBAApAQAAAA==.',
Ei='Eisheth:BAAALgAECgQJBQAAAA==.Eitent:BAACLgAFFH8JAAIXAAMJTxpyEQDaAAAXAAMJTxpyEQDaAAAuAAQKfzAAAxcACQm7HcUNAKoCABcACQm7HcUNAKoCAAIABwm6EhF2AI4BAAEuAAUUAwkKACAAqxMA.Eitentormu:BAAALgAECggJCAABLgAFFAMJCgAgAKsTAA==.',
El='Ele:BAAALgADCgcJCAABLgAFFAMJCQAXAAchAA==.Ellesthara:BAABLgAECn8UAAIBAAcJNwk/EwB3AAABAAcJNwk/EwB3AAAAAA==.Ellysiaa:BAABLgAECn8XAAIGAAYJ3QWeMgCVAAAGAAYJ3QWeMgCVAAAAAA==.Elrïc:BAAALgAECgYJEAAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn83AAQHAAkJdhZ+GQAAAgAHAAkJwRV+GQAAAgABAAcJMA0rWAAwAQAIAAQJ4xI8CgDZAAAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgAECgEJAQAAAA==.Enyxea:BAABLgAECn8bAAIFAAkJ8ReaKgARAgAFAAkJ8ReaKgARAgAAAA==.',
Ep='Ephemera:BAAALgAECgYJEQAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgAECgIJAwAAAA==.',
Es='Esman:BAAALgADCgMJAwAAAA==.Esmeray:BAEBLgAECn8nAAIgAAkJPBckAwAoAgAgAAkJPBckAwAoAgABLgAECgkJJwATAL8eAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAABLgAECn8kAAIDAAkJVh8LBADHAgADAAkJVh8LBADHAgAAAA==.Eyewana:BAABLgAECn8kAAINAAkJchKbHQCPAQANAAkJchKbHQCPAQAAAA==.',
Ez='Ezzka:BAACLgAFFH8RAAIRAAMJwSAbLQAbAQARAAMJwSAbLQAbAQAuAAQKfycAAhEACQkJHWkgAIcCABEACQkJHWkgAIcCAAAA.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJDgAAAA==.Fangalor:BAAALgAECgEJBAAAAA==.Farnsworth:BAABLgAECn8eAAQJAAkJ4R0KHwBqAgAJAAgJ+x0KHwBqAgAVAAMJGBxCIQCkAAAfAAEJNBPrOQBBAAAAAA==.Farzix:BAABLgAECn8qAAIKAAkJKQn3PABCAQAKAAkJKQn3PABCAQAAAA==.Façade:BAABLgAECn8mAAIRAAkJDxMYYACpAQARAAkJDxMYYACpAQAAAA==.',
Fe='Feelgood:BAAALgAFFAEJAQAAAA==.Fefifiona:BAACLgAFFH8FAAIgAAIJOA2fQAB3AAAgAAIJOA2fQAB3AAAuAAQKfxkAAiAACQkqF2sQAGoCACAACQkqF2sQAGoCAAAA.Fefifredrich:BAAALgAECgMJAwABLgAFFAIJBQAgADgNAA==.Fefifuredric:BAAALgAECgQJBQABLgAFFAIJBQAgADgNAA==.Felvira:BAABLgAECn8dAAMPAAgJPgTO1ACLAAAPAAYJbQPO1ACLAAANAAUJWwRCWgBZAAAAAA==.',
Fi='Finnw:BAACLgAFFH8JAAIXAAMJByGhDQAZAQAXAAMJByGhDQAZAQAuAAQKfyEAAhcABwneIOYQAI8CABcABwneIOYQAI8CAAAA.Firelite:BAABLgAECn8oAAIKAAkJYw/9OwBFAQAKAAkJYw/9OwBFAQAAAA==.',
Fl='Flairadin:BAAALgAECgQJBAAAAA==.Flairlock:BAABLgAECn8/AAMfAAkJZyGxAgCfAgAfAAkJZyGxAgCfAgAVAAIJBhW3PAA5AAAAAA==.Flee:BAABLgAECn8iAAITAAkJqRoKDwA7AgATAAkJqRoKDwA7AgAAAA==.Flexo:BAAALgAECgYJBQABLgAECgkJHgAJAOEdAA==.',
Fo='Fookster:BAABLgAECn8ZAAIMAAkJyhPfQAAaAgAMAAkJyhPfQAAaAgAAAA==.Forsetee:BAABLgAFFH8GAAIhAAIJTReHRACQAAAhAAIJTReHRACQAAAAAA==.',
Fr='Frowdawn:BAABLgAECn87AAIUAAkJUxCwBwDcAQAUAAkJUxCwBwDcAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAAEAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgARACoaAA==.',
Ga='Ga:BAAALgAECgIJAgAAAA==.Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAABLgAECn8pAAIbAAYJKhVvBQAoAQAbAAYJKhVvBQAoAQAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJMAARANYiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.Genericeric:BAAALgADCgQJBAAAAA==.',
Gi='Gilas:BAAALgADCgYJFQAAAA==.Gilf:BAAALgAECgEJAQABLgAECgcJDgAEAAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8xAAIBAAkJigzhRgB0AQABAAkJigzhRgB0AQAAAA==.Glizzygoblin:BAAALgAECgEJAQAAAA==.',
Go='Googoobler:BAABLgAECn8mAAINAAgJ7QmqLwAJAQANAAgJ7QmqLwAJAQAAAA==.Goudaluck:BAAALgADCgUJBwABLgAECgkJOAALAKoiAA==.Goudanight:BAAALgAECgMJBQABLgAECgkJOAALAKoiAA==.Goudavibes:BAAALgAECgEJAQABLgAECgkJOAALAKoiAA==.',
Gr='Greenmagus:BAAALgAECgQJBAAAAA==.Grenadon:BAABLgAECn8mAAIIAAYJ5AZHEAB7AAAIAAYJ5AZHEAB7AAAAAA==.Gridimbor:BAAALgAECgEJAQAAAA==.Grimlilith:BAABLgAECn8bAAQfAAgJ/wSbEQATAQAfAAgJ9gSbEQATAQAJAAMJBAMCMQE5AAAVAAEJAAAogQALAAAAAA==.Grimmhoof:BAAALgAECgIJAgAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gulem:BAAALgADCgYJBgAAAA==.Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn9AAAIdAAkJOx0NDQCCAgAdAAkJOx0NDQCCAgAAAA==.Hakitua:BAABLgAECn8mAAIOAAkJ2w1pDgBqAQAOAAkJ2w1pDgBqAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDgAAAA==.Hatshepsut:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn9EAAIWAAkJ0xCsBwBXAQAWAAkJ0xCsBwBXAQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Hearthledger:BAAALgADCgEJAQABLgAECgkJGgAKAP0SAA==.Heimdall:BAACLgAFFH8FAAMWAAUJhhFcHQC8AAAWAAQJjhFcHQC8AAAYAAEJbhHkHwBKAAAuAAQKf0cABBsACQkGJsYAAGkDABsACQkGJsYAAGkDABYACQnWG44eAPoBABgAAwm/EB5NAJsAAAAA.Heis:BAABLgAECn8qAAIWAAcJbRyCAwD5AQAWAAcJbRyCAwD5AQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8xAAICAAkJABcwQwD9AQACAAkJABcwQwD9AQAAAA==.',
Hi='Hiko:BAABLgAECn8fAAMhAAgJjhDJBQDvAAAhAAgJjhDJBQDvAAAZAAEJggNDugAfAAAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMFAAYJJgqFAgC9AQAFAAYJJgqFAgC9AQAKAAUJFB/mHQAuAQAuAAQKfyEAAwoACQlzIWYDAG0DAAoACQlzIWYDAG0DAAUABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgAFACYKAA==.Holyangus:BAAALgAECgUJDQAAAA==.Holyfawn:BAAALgADCgEJAQAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.Housemom:BAAALgAECgEJAQAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.Hulahoof:BAAALgAECgcJDgAAAA==.',
Ib='Ibbert:BAAALgAECgEJAQAAAA==.',
Ic='Icculus:BAABLgAECn8sAAILAAgJzxuQBgAlAgALAAgJzxuQBgAlAgAAAA==.Iceticles:BAAALgAECgYJBQAAAA==.',
Il='Illuyanka:BAAALgAECgIJAgAAAA==.',
Im='Imaresmashy:BAAALgAECgMJAwABLgAECgkJJAAEAAAAAA==.Impasse:BAAALgAECgkJCAAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8+AAIhAAkJaSTgAQBKAwAhAAkJaSTgAQBKAwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgAEAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Iy='Iyrus:BAAALgAECgkJCQAAAA==.',
Ja='Jacolynn:BAABLgAECn8ZAAIaAAcJBRLsKwBXAQAaAAcJBRLsKwBXAQAAAA==.Jaenei:BAAALgAECgcJDwAAAA==.',
Je='Jeeb:BAAALgAECgcJDAAAAA==.Jelly:BAAALgADCgIJAgAAAA==.',
Ji='Jinrok:BAAALgAECgUJBgAAAA==.Jinxta:BAAALgAECgQJBAAAAA==.',
Jo='Joansnow:BAAALgAECgcJBwABLgAECgkJJwAaAAAWAA==.Joatmoa:BAACLgAFFH8GAAIGAAMJNRTlDQDbAAAGAAMJNRTlDQDbAAAuAAQKfxQAAgYACQmIHP8PALcBAAYACQmIHP8PALcBAAAA.Joeexotics:BAAALgADCgkJDAAAAA==.Johnlebron:BAAALgAECgEJAwABLgAECgcJDgAEAAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECggJEgAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCggJJgAAAA==.',
Ka='Kaelnis:BAAALgAECggJEgAAAA==.Kaimargonar:BAABLgAECn8eAAIVAAgJkhamCwCFAQAVAAgJkhamCwCFAQAAAA==.Kaitoi:BAABLgAECn8jAAMGAAkJ7BzPBACtAgAGAAkJ7BzPBACtAgAIAAUJKwi0TAB4AAAAAA==.Kalinth:BAAALgADCgIJAgAAAA==.Kallah:BAACLgAFFH8lAAIXAAgJcB8ZCAA/AgAXAAgJcB8ZCAA/AgAuAAQKfzcAAhcACQnsI44BAGsDABcACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn9BAAQiAAkJHBkSCQBZAgAiAAgJjxkSCQBZAgAjAAkJnBGJBwDCAQAkAAEJMRmmGABDAAAAAA==.Kamakizeg:BAACLgAFFH8FAAICAAIJIQ1SkwCNAAACAAIJIQ1SkwCNAAAuAAQKfzUAAgIACQk4GKsJAMUBAAIACQk4GKsJAMUBAAAA.Kamayla:BAAALgAECgYJBgAAAA==.Karnus:BAAALgADCgUJBQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAACLgAFFH8LAAIMAAMJkR5LLQAXAQAMAAMJkR5LLQAXAQAuAAQKfygAAgwACQl2HaQhAJcCAAwACQl2HaQhAJcCAAEuAAUUAwkRABEAwSAA.Katimalice:BAAALgAECgUJBQAAAA==.',
Ke='Keathry:BAAALgADCgMJBQAAAA==.Kestrelle:BAABLgAECn8ZAAIQAAcJCQo9CwDjAAAQAAcJCQo9CwDjAAABLgAECgkJXAABAPkSAA==.Keyzeus:BAABLgAECn8lAAMjAAgJCxibBgDjAQAjAAgJCxibBgDjAQAkAAEJ5xsAhwBOAAAAAA==.',
Kh='Khas:BAAALgADCgkJHQAAAA==.Khui:BAACLgAFFH8lAAMaAAgJeiQDCgBoAgAaAAgJeiQDCgBoAgAZAAQJ0hpKBgA9AQAuAAQKfycAAxoACQlIJMACAFcDABoACQlIJMACAFcDABkABAnnGrdSAL4AAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBwAAAA==.Killian:BAAALgAECgYJBgAAAA==.Kipziep:BAAALgAECgIJAgAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8bAAMRAAgJ2xekJQDWAQARAAcJ2xekJQDWAQASAAEJAAB8VgAAAAAuAAQKfykAAhEACQn9INMSAAsDABEACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8rAAIaAAkJ/RciFgBpAgAaAAkJ/RciFgBpAgABLgAFFAgJGwARANsXAA==.',
Ko='Koltharaz:BAABLgAFFH8IAAIkAAUJqAcxGADjAAAkAAUJqAcxGADjAAAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAAEAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.Kozatra:BAAALgAECgUJCAAAAA==.',
Kr='Krankthas:BAAALgAECgIJAgABLgAECgIJBAAEAAAAAA==.Krazylock:BAAALgAECgQJCQAAAA==.Krazysniper:BAABLgAECn8oAAMLAAgJCRy0MAAZAgALAAcJEB+0MAAZAgAlAAEJ4wmKYgA3AAAAAA==.Kreepa:BAAALgAECgEJAQAAAA==.Krokk:BAABLgAECn8UAAIKAAcJ9QdiVQDlAAAKAAcJ9QdiVQDlAAAAAA==.Kruulock:BAAALgADCgcJBwAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAFFAEJAQABLgAFFAYJHgAEAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMCAAgJFh66KgB5AgACAAgJFh66KgB5AgAXAAYJOBheOwBbAQAAAA==.Lacosanostra:BAABLgAECn8UAAMZAAYJ2wRfEQBuAAAZAAYJ2wRfEQBuAAAaAAMJkQRjMwA6AAAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lancedragon:BAAALgADCgEJAQAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgACABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8rAAILAAkJjxi2TwCzAQALAAkJjxi2TwCzAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgkJJAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lenard:BAAALgAECgEJAQAAAA==.Lezsul:BAAALgAECgIJAgAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8fAAICAAcJAhIflgBIAQACAAcJAhIflgBIAQAAAA==.Lightguard:BAABLgAECn8XAAMCAAkJoAYOKACsAAACAAUJJgcOKACsAAADAAYJLgT6DwBfAAAAAA==.Lighthouse:BAABLgAECn8wAAICAAkJlxtFNQArAgACAAkJlxtFNQArAgAAAA==.Lileth:BAAALgAECggJCwAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgAECgIJAgAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lolalazer:BAABLgAECn8WAAIPAAgJ9RVJWwB2AQAPAAgJ9RVJWwB2AQAAAA==.Lolhahabaha:BAAALgAECggJDQAAAA==.Loopie:BAAALgADCgYJCgAAAA==.Loranthyr:BAAALgADCgQJBAAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8fAAISAAgJURR/BgAoAQASAAgJURR/BgAoAQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgkJHwALAPgfAA==.',
Ly='Lypally:BAABLgAECn9OAAICAAkJrRtmBQBPAgACAAkJrRtmBQBPAgAAAA==.',
['Là']='Làdedá:BAAALgAECgYJDgAAAA==.',
['Lï']='Lïllïth:BAAALgAECgkJEQAAAA==.Lïly:BAAALgADCggJEAABLgAECgkJJAAEAAAAAA==.',
['Ló']='Lóla:BAABLgAECn8wAAIPAAkJziMYCAAPAwAPAAkJziMYCAAPAwAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8qAAMTAAkJyxOLBQBkAgATAAkJyxOLBQBkAgAUAAYJOw8xAwBvAQAuAAQKfyEAAxMACAlGHtkMAMsCABMACAlGHtkMAMsCABQAAQnoGt8aAFEAAAAA.Magegrizz:BAAALgAECgcJCQAAAA==.Mahimahi:BAAALgAECggJCAAAAA==.Mardain:BAABLgAECn8fAAImAAkJphVTCgAUAgAmAAkJphVTCgAUAgAAAA==.Mariacuras:BAABLgAECn8WAAIXAAkJ7AqDMQCRAQAXAAkJ7AqDMQCRAQAAAA==.Marle:BAABLgAECn87AAIPAAkJ1RiqBADkAQAPAAkJ1RiqBADkAQAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgAECgUJCAAAAA==.Martis:BAAALgAFFAEJAgAAAA==.Marynne:BAABLgAECn9cAAMBAAkJ+RLdBgBpAQABAAkJ+RLdBgBpAQAHAAEJSwKerAAMAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8zAAMOAAkJvxc0BwASAgAOAAkJUBc0BwASAgANAAIJ7xmYEACMAAAAAA==.',
Mc='Mcdo:BAAALgAFFAIJAgABLgAFFAgJGgAnACYbAA==.Mctank:BAAALgAECgEJAQAAAA==.',
Me='Mecandry:BAAALgAECgEJAQABLgAECgkJNQACANcKAA==.Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgAECgUJBQAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8wAAMdAAgJhQ8nKgCAAQAdAAgJhQ8nKgCAAQAQAAUJxQwWTgCqAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAABLgAECn8xAAQCAAkJTxwgBACJAgACAAkJTxwgBACJAgAXAAYJ6A8cEgB2AAADAAIJRg2HEgBPAAABLgAECgkJMgANAOEfAA==.Meliza:BAAALgAECgEJAQABLgAECgYJEAAEAAAAAA==.Merrikeath:BAABLgAECn8cAAIRAAkJPgg7GQDeAAARAAkJPgg7GQDeAAAAAA==.Merriklade:BAABLgAECn8zAAMbAAkJAA8oFwCKAQAbAAkJRw4oFwCKAQAWAAgJzQozOwBZAQAAAA==.Merrikoid:BAAALgAECgUJCAAAAA==.Merrikwolf:BAAALgAECgYJDgAAAA==.',
Mi='Misamina:BAAALgAECgMJAwAAAA==.Missyjelliot:BAAALgAECggJDwAAAA==.',
Mo='Monster:BAAALgADCgEJAQAAAA==.Moof:BAAALgADCgEJAQAAAA==.Morbidstyle:BAAALgAECgYJCgABLgAFFAYJGgALAOAVAA==.Morchuk:BAAALgADCgMJAwAAAA==.Morigith:BAAALgAECgQJBwABLgAECgYJEAAEAAAAAA==.Morthos:BAAALgAECgUJCAAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAFFAMJCQAXAAchAA==.',
My='Myora:BAEBLgAECn8nAAITAAkJvx7cAADUAgATAAkJvx7cAADUAgAAAA==.Mythundirus:BAAALgADCgMJAwAAAA==.',
['Mà']='Màrli:BAABLgAECn8YAAMSAAkJbBHDBAB3AQASAAkJbBHDBAB3AQAcAAcJ8QiDGgD8AAAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8iAAIDAAkJQRPcEQCoAQADAAkJQRPcEQCoAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQAYADUeAA==.Nakasid:BAACLgAFFH8KAAIQAAMJYxEBIgCqAAAQAAMJYxEBIgCqAAAuAAQKfz4ABBAACQl5GSQDAAoCABAACQl5GSQDAAoCAB0ABwkVCNQ5ACIBACAABAlbCntcAI0AAAAA.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Naura:BAAALgADCgMJAwAAAA==.Navane:BAAALgAECgUJBwAAAA==.',
Ne='Necromaniac:BAAALgAECgEJAQAAAA==.Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8rAAIPAAkJsBDpQwC8AQAPAAkJsBDpQwC8AQAAAA==.Nevaehstar:BAACLgAFFH8GAAIeAAMJfBG/AgC4AAAeAAMJfBG/AgC4AAAuAAQKf0sAAh4ACQnzJDEAAPcCAB4ACQnzJDEAAPcCAAAA.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJDQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8wAAIQAAkJOxQKIADDAQAQAAkJOxQKIADDAQAAAA==.Nik:BAAALgAECgkJCQAAAA==.Nikolia:BAABLgAECn8WAAMbAAgJQw5mCADCAAAbAAUJfRBmCADCAAAWAAYJJggPFQCaAAAAAA==.Ninetynine:BAAALgADCgMJBQAAAA==.Nini:BAABLgAECn8nAAIHAAgJvgKcXQCgAAAHAAgJvgKcXQCgAAAAAA==.Ninx:BAAALgAECggJDQAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAYJEQANAA4TAA==.Nokru:BAAALgADCgMJBQAAAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgAECgkJCQAAAA==.',
Ny='Nyctelodeon:BAAALgADCgcJBwAAAA==.',
Nz='Nzuul:BAABLgAECn8fAAIPAAYJuwlmGgCvAAAPAAYJuwlmGgCvAAAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAwAAAA==.',
Om='Ominous:BAAALgAECgMJAwAAAA==.',
On='Onram:BAAALgAECgEJAQAAAA==.',
Op='Oppaissiah:BAABLgAECn9EAAMbAAkJ6iNPAgAlAwAbAAkJlSNPAgAlAwAWAAkJ8R/7CQDDAgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAIkAAYJawJudgB5AAAkAAYJawJudgB5AAABLgAECgkJEgAEAAAAAA==.Orico:BAAALgAECgQJBAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.Orman:BAAALgAFFAIJAgAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAABLgAECgkJNQACANcKAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJDAAAAA==.Padrizul:BAAALgADCgEJAQAAAA==.Pandamared:BAAALgADCggJCgAAAA==.Papasbich:BAABLgAECn8lAAINAAcJawk2DADHAAANAAcJawk2DADHAAABLgAFFAMJCgACAG0FAA==.Papasfury:BAAALgAECgkJAQABLgAFFAMJCgACAG0FAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Ph='Phantazm:BAAALgADCgEJAQAAAA==.Phenol:BAAALgADCgUJBQAAAA==.Phoxie:BAAALgAECgEJAQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Polog:BAAALgAECgMJAwABLgAECgkJLgARADwlAA==.Porkchoplust:BAAALgAECgcJCQAAAA==.Porkchopw:BAAALgAECgcJAgAAAA==.Porkribs:BAABLgAFFH8HAAIXAAMJ2RbfEgDIAAAXAAMJ2RbfEgDIAAAAAA==.',
Pr='Presap:BAABLgAECn8zAAMBAAkJBCJuBQBhAwABAAkJBCJuBQBhAwAHAAEJAACrdgBJAAABLgAECgkJGQAiAKwcAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAABLgAECn8pAAIGAAYJih5YAgC3AQAGAAYJih5YAgC3AQAAAA==.Pumdmuc:BAACLgAFFH8TAAIQAAUJWRrhBwA/AQAQAAUJWRrhBwA/AQAuAAQKf0wAAxAACQnlIdoGAN8CABAACQnlIdoGAN8CAB0ABwkqBbVTAMMAAAAA.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJEAAAAA==.',
Qu='Quikglaives:BAAALgAFFAMJBAAAAA==.Quille:BAABLgAECn8iAAILAAkJRyPzDgDZAgALAAkJRyPzDgDZAgAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIDAAkJrRJqEQCuAQADAAkJrRJqEQCuAQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgMJBAAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJDAAAAA==.Redrek:BAAALgADCggJMgAAAA==.Redsbank:BAAALgADCgMJBgAAAA==.Redshunter:BAAALgADCgcJFgAAAA==.Redsknight:BAAALgAECgEJAQAAAA==.Redsmonk:BAAALgADCgcJFwAAAA==.Redwinter:BAAALgAECgIJBAABLgAECggJHwAWAPcbAA==.Reikisong:BAAALgAECggJDQAAAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reylia:BAAALgAECgQJBAAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhagurion:BAAALgAFFAEJAgAAAA==.Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8tAAMBAAgJbBchBADrAQABAAgJbBchBADrAQAHAAEJignKJgAlAAAAAA==.',
Ro='Rockmonsta:BAAALgAECgUJCgAAAA==.Rockrat:BAAALgADCgEJAQAAAA==.Rodeo:BAABLgAECn8sAAIHAAkJABCiIwCtAQAHAAkJABCiIwCtAQAAAA==.Rotgutwiskey:BAAALgAECgIJAgAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.Royan:BAABLgAECn8VAAIQAAkJ6Q8ABQCjAQAQAAkJ6Q8ABQCjAQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAIPAAYJeQ6eegA4AQAPAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAFFAEJAQAAAA==.Sadnhornless:BAAALgAECgEJAwAAAA==.Saeti:BAACLgAFFH8XAAMGAAQJex7ICQARAQAGAAMJfiDICQARAQAHAAEJbxiNSQBMAAAuAAQKf0YABQYACQlzJIUCAKkBAAYACQmII4UCAKkBAAcABgkKH4kIADEBAAgABAk2HlIrAAQBAAEABAkUFoqIAKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sanh:BAAALgAECgEJAQAAAA==.Sapplesauce:BAABLgAECn8XAAITAAgJ5Bc9HgCkAQATAAgJ5Bc9HgCkAQAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Sedael:BAAALgAECgIJAgABLgAECgYJKQAXAKsjAA==.Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAACLgAFFH8MAAMBAAMJQgmHIABvAAABAAMJQgmHIABvAAAHAAEJ4wYnUQA0AAAuAAQKf1gAAwEACQkwH/ALAAEDAAEACQkwH/ALAAEDAAcABgmbE5Y4ADEBAAAA.',
Sh='Shadý:BAABLgAECn8vAAILAAkJ5AoTVgCiAQALAAkJ5AoTVgCiAQAAAA==.Shamanoodles:BAAALgAECgEJAwABLgAECgkJLgARADwlAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQVAAgJLBqNCwCIAQAJAAgJ1hcKRADPAQAVAAcJeBiNCwCIAQAfAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn9OAAIWAAkJIR1fDgCLAgAWAAkJIR1fDgCLAgAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sianu:BAABLgAECn8bAAIFAAcJTw6bDgA1AQAFAAcJTw6bDgA1AQABLgAECgkJXAABAPkSAA==.Sidarya:BAABLgAECn8ZAAMQAAgJgRcDGgD7AQAQAAgJgRcDGgD7AQAdAAIJZgckKQAoAAAAAA==.Sidera:BAAALgAECggJDgAAAA==.Sidraya:BAAALgAECgEJBAAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Sidusa:BAAALgADCgcJCgAAAA==.Silent:BAACLgAFFH8bAAMWAAQJxB79FQBeAQAWAAQJxB79FQBeAQAYAAEJPAxiQgBDAAAuAAQKfx4AAxgACQmjFs4ZACUBABYABwlxFW5EADQBABgABgkoEs4ZACUBAAAA.Silveric:BAAALgADCgYJCQAAAA==.Silverserket:BAAALgAECgIJBAAAAA==.Silverserqet:BAABLgAECn8WAAILAAcJgA5LhAA2AQALAAcJgA5LhAA2AQAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn9SAAMFAAkJQBYGBwDYAQAFAAkJQBYGBwDYAQAKAAgJQAiaSgAKAQAAAA==.Skyscales:BAEALgAECgcJBwABLgAECgkJUgAFAEAWAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.Slipknaught:BAAALgAECgQJAwABLgAECgkJJwAaAAAWAA==.',
Sm='Smileyriley:BAABLgAECn8bAAIHAAcJcgbfTwDOAAAHAAcJcgbfTwDOAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBQABLgAECgcJDgAEAAAAAA==.Snot:BAAALgADCgEJAQAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.Snèakyboots:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAABLgAECn8XAAIaAAUJCwRzlQBtAAAaAAUJCwRzlQBtAAAAAA==.Solarêclipse:BAAALgAECgUJBgAAAA==.Sooki:BAAALgAECgIJBAAAAA==.Sorath:BAAALgAECgMJAwAAAA==.Sorilea:BAAALgADCgkJGQAAAA==.Sorlis:BAAALgAECgcJEwAAAA==.Soulber:BAABLgAECn8bAAMRAAkJwRTjWAC7AQARAAkJ5RPjWAC7AQASAAIJnxxUPACgAAAAAA==.Sourdew:BAABLgAECn8eAAIZAAcJtB7ZGQDiAQAZAAcJtB7ZGQDiAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8ZAAMiAAkJrBwjBADzAgAiAAkJrBwjBADzAgAjAAEJAAA/LwAAAAAAAA==.Splashgordon:BAAALgAECgQJBAABLgAECgkJGQAiAKwcAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwAEAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgUJCwAAAA==.Stefeana:BAAALgAECgYJBgAAAA==.Stelle:BAABLgAECn8XAAIgAAgJBBEYJABzAQAgAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgIJAgAAAA==.Stylos:BAABLgAECn9BAAImAAgJPBclDADwAQAmAAgJPBclDADwAQAAAA==.Stãrburst:BAABLgAECn8UAAMFAAgJZQr4ewDsAAAFAAcJswf4ewDsAAAKAAEJUASqvwAeAAAAAA==.',
Su='Subrinea:BAAALgAECgUJBQABLgAFFAMJBgAeAHwRAA==.Sumofwhy:BAAALgAECgMJAwAAAA==.',
Sw='Swowtitbang:BAAALgAECgYJBgAAAA==.',
Sy='Sylven:BAAALgADCgYJBgABLgAFFAUJBQAWAIYRAA==.',
Ta='Taissa:BAAALgADCggJCwAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECggJEwAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQSAAgJNBm8EwDXAQASAAgJVBi8EwDXAQARAAgJBQ8oZwDAAQAcAAEJAACfGgAeAAABLgAECgkJDgAEAAAAAA==.Tegmage:BAAALgAECgUJBQABLgAECgkJDgAEAAAAAA==.Tempestrike:BAAALgAFFAIJAwAAAA==.Terentia:BAEALgAECgcJDAABLgAECgkJJwATAL8eAA==.',
Th='Thadind:BAAALgAECgQJBQAAAA==.Thalodrim:BAAALgAECgEJAQABLgAECgkJHgAJAOEdAA==.Tharelly:BAABLgAECn8XAAIMAAkJrxi6OwArAgAMAAkJrxi6OwArAgAAAA==.Thasserian:BAAALgADCgIJAgABLgAFFAUJBQAWAIYRAA==.Theholymatt:BAACLgAFFH8XAAMXAAcJqxZBFgB2AQAXAAUJAxRBFgB2AQACAAUJBRbnIAAIAQAuAAQKf0oAAwIACQlVJUcIACkDAAIACQlVJUcIACkDABcABwnnJEEPAJsCAAAA.Thendari:BAABLgAECn+LAAIVAAkJCRrWAABIAgAVAAkJCRrWAABIAgAAAA==.Theodus:BAABLgAECn81AAIMAAkJhxlIOAA3AgAMAAkJhxlIOAA3AgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAIkAAgJfxorHAD0AQAkAAgJfxorHAD0AQABLgAFFAcJFwAXAKsWAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn9PAAMYAAkJYiSUAgAfAwAYAAkJJSSUAgAfAwAWAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8YAAMXAAcJhBbaEQClAQAXAAcJhBbaEQClAQACAAMJpwNXRACSAAAuAAQKfz0AAhcACQn3IDgFAEADABcACQn3IDgFAEADAAAA.Tislam:BAABLgAECn8bAAIJAAkJag6zaABrAQAJAAkJag6zaABrAQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQYAAkJNR7NBACaAgAYAAkJFhrNBACaAgAbAAcJpSCYDwDuAQAWAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn9RAAIQAAkJMR2AAQCtAgAQAAkJMR2AAQCtAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIbAAkJJBMGFACvAQAbAAkJJBMGFACvAQABLgAECgQJBAAEAAAAAA==.Torolf:BAAALgAECgcJEQAAAA==.Torsen:BAAALgADCgcJCAAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgQJBAAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8gAAMKAAgJ5BRyCAAsAgAKAAgJ5BRyCAAsAgAFAAEJYAwCegBLAAAuAAQKf0gAAgoACQnMIswEABQDAAoACQnMIswEABQDAAAA.',
Ts='Tsonokwabain:BAABLgAECn8rAAQcAAkJhyKlAQAYAwAcAAkJhyKlAQAYAwASAAEJah2JVABIAAARAAEJmALGpgEYAAAAAA==.Tsunami:BAAALgADCgYJCAAAAA==.',
Tu='Tumnus:BAAALgADCgMJBAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tye:BAAALgAFFAEJAgAAAA==.Tyranastrasz:BAABLgAECn8+AAQiAAkJjhdIAgCTAQAiAAkJjhdIAgCTAQAjAAEJ6gYPKQAqAAAkAAEJWQQLHwAfAAAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAITAAkJ4QXSKABRAQATAAkJ4QXSKABRAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAABLgAFFH8FAAIRAAIJPhWVfwBaAAARAAIJPhWVfwBaAAAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAIPAAgJOxgFTgCcAQAPAAgJOxgFTgCcAQAAAA==.Vaerryn:BAABLgAECn8mAAQcAAgJMyOABgA8AgAcAAcJFiOABgA8AgARAAMJcBv80gDkAAASAAIJQyCDUQBPAAAAAA==.Vaethund:BAAALgAECgkJEwAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAAOAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Valkz:BAAALgADCgEJAQAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vaneesha:BAAALgADCgMJBgAAAA==.Vanesah:BAAALgAECgQJCAAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAABLgAECn8bAAMlAAkJ5ww1KABeAQAlAAcJxQw1KABeAQALAAgJ1wou1ACjAAAAAA==.Vassyra:BAEBLgAECn8rAAIjAAkJJBdOBQAOAgAjAAkJJBdOBQAOAgABLgAECgkJJwATAL8eAA==.',
Ve='Velara:BAAALgAECgcJDAAAAA==.Velesyn:BAABLgAECn8cAAMOAAgJUx9UBwAOAgAOAAcJKCBUBwAOAgAPAAIJtxH7/QBOAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.Venekor:BAAALgADCgUJBQAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.Vitoria:BAAALgAECgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAACLgAFFH8KAAIgAAMJqxNHHAClAAAgAAMJqxNHHAClAAAuAAQKfygAAyAACQlbGWgMAKcCACAACQlbGWgMAKcCAB0ACAnVFwYaAPUBAAAA.Volundr:BAABLgAECn9AAAIbAAkJ7xgNDgAKAgAbAAkJ7xgNDgAKAgAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECgkJGwAZAOEhAA==.',
Vy='Vynel:BAAALgAECgYJCQABLgAFFAUJBQAWAIYRAA==.Vynirion:BAABLgAECn8UAAIMAAcJqxJUpACPAQAMAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAABLgAECn8iAAITAAkJPQcDBgAoAQATAAkJPQcDBgAoAQAAAA==.Wardellmo:BAAALgAECgEJAQAAAA==.Wargtar:BAABLgAECn84AAITAAgJlCH8DQBIAgATAAgJlCH8DQBIAgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8bAAMQAAcJ4BKKNgAmAQAQAAcJ4BKKNgAmAQAgAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJDwAAAA==.',
Wh='Whatcow:BAAALgAFFAEJAQAAAA==.Whiteback:BAAALgADCgUJBQAAAA==.Whiterrina:BAAALgADCgkJCgAAAA==.',
Wi='Window:BAAALgAECgEJAQAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8jAAMHAAkJ9AjhMgBPAQAHAAkJ9AjhMgBPAQABAAUJZwnQiwCfAAAAAA==.Wyrdo:BAAALgAECgYJBgAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAILAAkJywobVgBmAQALAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn87AAMFAAkJDSMoDQDuAgAFAAkJDSMoDQDuAgAKAAcJVhsABgCGAQAAAA==.',
Xk='Xkwizet:BAABLgAECn8aAAIMAAgJPgcsoQA5AQAMAAgJPgcsoQA5AQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgAECgEJAQAAAA==.',
Ya='Yasuke:BAAALgAECgQJBQAAAA==.',
Ye='Yet:BAABLgAECn85AAMCAAkJWiVTBQBKAwACAAkJWiVTBQBKAwAXAAYJpBuxAwDlAQAAAA==.',
Yi='Yiffweaver:BAABLgAECn80AAIhAAkJKAymAwBXAQAhAAkJKAymAwBXAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn80AAIDAAkJfhNXEAC/AQADAAkJfhNXEAC/AQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAABLgAECn8jAAIHAAkJ0AlPDADkAAAHAAkJ0AlPDADkAAAAAA==.',
Za='Zarhianna:BAABLgAECn8lAAIHAAkJgBBHIgC3AQAHAAkJgBBHIgC3AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.Zephnor:BAAALgAECgkJEQAAAA==.',
Zm='Zmona:BAABLgAECn8xAAICAAkJHg+aZwCgAQACAAkJHg+aZwCgAQAAAA==.',
Zo='Zorsche:BAAALgAECgUJDQAAAA==.',
Zu='Zulrok:BAABLgAECn8vAAIWAAkJUR7wEgBbAgAWAAkJUR7wEgBbAgAAAA==.',
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
