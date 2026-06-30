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

local lookup = {'Druid-Restoration','Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Warlock-Affliction','DeathKnight-Blood','Priest-Discipline','Monk-Brewmaster','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abrácadabra:BAAALgAECgMJAwABLgAECgkJPwABAOgVAA==.',
Ac='Achilles:BAAALgAECgEJAQAAAA==.',
Ad='Aderan:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAACAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJMwADAAYhAA==.Aesalon:BAABLgAECn80AAQEAAkJ1CMHBADHAgAEAAkJ1CMHBADHAgAFAAIJrRTjeQA+AAAGAAIJGBMIcwA0AAABLgAECgkJHgAHAOEdAA==.',
Ah='Ahsokatano:BAABLgAECn8zAAMDAAkJBiFuBwA5AwADAAkJBiFuBwA5AwAIAAEJ8gwQswAnAAAAAA==.',
Ai='Aimspet:BAABLgAECn8WAAIDAAYJmBOKXwA+AQADAAYJmBOKXwA+AQAAAA==.Aircanada:BAAALgAECgIJBAAAAA==.',
Ak='Akela:BAABLgAECn8oAAIJAAkJIQ1sTQC6AQAJAAkJIQ1sTQC6AQAAAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAAALgAECgcJEgAAAA==.Amonet:BAABLgAECn8VAAIKAAYJygfMDwDBAAAKAAYJygfMDwDBAAAAAA==.',
An='Anaelcheese:BAABLgAECn8cAAQLAAcJ1xoPIwBfAQALAAcJ1xoPIwBfAQAMAAEJkg0sLgAnAAANAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8uAAIOAAkJmBR2IQC3AQAOAAkJmBR2IQC3AQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAABLgAECn8/AAIPAAkJORhZLwBCAgAPAAkJORhZLwBCAgAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgAECgcJBwAAAA==.Anolana:BAABLgAECn8+AAMQAAkJZiL6BADoAgAQAAkJZiL6BADoAgARAAEJixEPJwA3AAAAAA==.Anrom:BAAALgAECgEJAQAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn9CAAISAAkJlRd5AADvAQASAAkJlRd5AADvAQAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Ariûs:BAABLgAECn8YAAITAAgJQhJrLQCcAQATAAgJQhJrLQCcAQAAAA==.Arlin:BAABLgAECn8bAAIUAAYJLSPNAABIAgAUAAYJLSPNAABIAgAAAA==.Arlorian:BAABLgAECn85AAIRAAkJLhWJBQAeAgARAAkJLhWJBQAeAgAAAA==.Arorra:BAAALgAECgYJBgAAAA==.Arrex:BAAALgAECgYJCAAAAA==.Arrowsmites:BAABLgAECn8zAAIJAAkJhRx5HQB0AgAJAAkJhRx5HQB0AgAAAA==.',
Au='Aubani:BAABLgAECn8xAAMUAAkJFCBlCQD1AgAUAAkJFCBlCQD1AgAVAAUJIxII2wDkAAAAAA==.',
Ax='Axelot:BAAALgAECgQJAwAAAA==.',
Ay='Ayperos:BAABLgAECn9WAAMWAAkJ6BtrAABVAgAWAAkJ6BtrAABVAgATAAYJPxAVUgBhAQAAAA==.Ayvaria:BAEALgAECgYJEwABLgAECgkJGwAQANURAA==.',
Az='Azorus:BAAALgADCgEJAQAAAA==.',
Ba='Baboyago:BAAALgAECggJEQAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Bahemith:BAAALgAECgEJAQAAAA==.Baked:BAAALgAECgQJBAABLgAECgkJJwAVAH0IAA==.Bakedpally:BAABLgAECn8nAAIVAAkJfQhwEQCqAAAVAAkJfQhwEQCqAAAAAA==.Bandomar:BAABLgAECn8mAAIFAAgJywvUNQA/AQAFAAgJywvUNQA/AQAAAA==.Baniemo:BAAALgAECgIJBAAAAA==.Banigor:BAAALgAECgYJEgAAAA==.Basak:BAAALgAECgYJCwABLgAFFAUJFwACAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn81AAIVAAkJliEuEgDXAgAVAAkJliEuEgDXAgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJDwAAAA==.Belithsong:BAAALgAECgkJBwAAAA==.Bereth:BAABLgAECn8YAAIJAAYJGBWdiAAtAQAJAAYJGBWdiAAtAQAAAA==.Berreydingle:BAAALgAECgUJEAAAAA==.',
Bi='Bigfuut:BAAALgADCgEJAQAAAA==.Bigkitty:BAABLgAECn8qAAITAAkJnhlLGgAbAgATAAkJnhlLGgAbAgABLgAECgkJNgAJAKoiAA==.Bikinibrenda:BAAALgAFFAMJAwAAAA==.Birchum:BAAALgADCgcJBwAAAA==.Biz:BAAALgADCgYJBwABLgAECgkJGQAXAJAhAA==.',
Bl='Blackanvil:BAABLgAECn8aAAITAAgJ7BBlBQDxAAATAAgJ7BBlBQDxAAAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECggJHwATAPcbAA==.Blackhuuf:BAAALgADCgkJDAAAAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAABLgAECn8hAAMYAAkJhBKQKgDYAQAYAAkJhBKQKgDYAQAXAAIJ5g2tlQA6AAAAAA==.Bloodsmage:BAAALgAECgMJAwAAAA==.Bloodymagi:BAABLgAECn8sAAIKAAkJhQfJgwBwAQAKAAkJhQfJgwBwAQAAAA==.Bluesummer:BAABLgAECn8fAAQTAAgJ9xsNJQDOAQATAAcJrR4NJQDOAQAZAAYJxBrAGQCCAQAWAAEJCAzpQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMGAAkJuhoBCgBIAgAGAAkJuhoBCgBIAgAFAAQJdQbVbQBtAAAAAA==.Borat:BAAALgAECgUJCgABLgAECgkJMwAVAFolAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAABLgAECn8ZAAIXAAkJkCH+CQCjAgAXAAkJkCH+CQCjAgAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECggJDwAAAA==.Bròly:BAAALgADCgYJBgAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIaAAkJIxS3DgCKAQAaAAkJIxS3DgCKAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calquo:BAAALgAECgMJAwABLgAECggJNgAQACEgAA==.Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgAECgIJBQAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgAECgYJEwAAAA==.Castration:BAABLgAECn8YAAIbAAYJ3AmOTgDVAAAbAAYJ3AmOTgDVAAAAAA==.',
Ce='Ceylan:BAABLgAECn8xAAMKAAkJgxlpMABXAgAKAAkJgxlpMABXAgAcAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgYJCwAAAA==.Charavane:BAAALgAECgQJBAAAAA==.Charlz:BAABLgAECn8jAAMbAAkJhBZ4HADhAQAbAAkJhBZ4HADhAQAOAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheat:BAAALgAECgYJBgAAAA==.Cheatdr:BAABLgAECn8tAAIBAAkJLA/6NQDCAQABAAkJLA/6NQDCAQAAAA==.Cheatpriest:BAABLgAECn89AAIOAAkJmxlpGgD3AQAOAAkJmxlpGgD3AQAAAA==.Chepis:BAAALgAECgUJBQAAAA==.Chesthyr:BAAALgAECgEJAgAAAA==.Chesto:BAABLgAECn89AAQdAAkJ7hx7BABVAgAdAAkJZBp7BABVAgASAAcJ4xplCgCeAQAHAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgAECgIJAgAAAA==.Chimken:BAAALgAECgcJCAABLgAECgkJKQAWADUeAA==.Chokea:BAAALgAECgkJDwAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.Chyrstal:BAAALgAECgEJAQAAAA==.',
Ci='Cindrethresh:BAAALgAECgUJBQAAAA==.',
Co='Cognition:BAACLgAFFH8JAAIJAAMJcRszFAD6AAAJAAMJcRszFAD6AAAuAAQKf2wAAgkACQkcJl0BAIMDAAkACQkcJl0BAIMDAAAA.Coldvengance:BAABLgAECn89AAITAAkJAQpoNgBuAQATAAkJAQpoNgBuAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAACAAAAAA==.Cranknstein:BAAALgAECgIJAgABLgAECgIJBAACAAAAAA==.Crazycalla:BAAALgAFFAIJAwAAAA==.Crosbyy:BAAALgAECgUJCgAAAA==.Crànk:BAAALgAECgIJAwABLgAECgIJBAACAAAAAA==.',
Cy='Cymindel:BAABLgAECn84AAIeAAkJCxrgDAA+AgAeAAkJCxrgDAA+AgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Daithi:BAABLgAECn8UAAIfAAYJXgtJQAAKAQAfAAYJXgtJQAAKAQAAAA==.Dakotà:BAABLgAECn8uAAIJAAkJyBtLLwAfAgAJAAkJyBtLLwAfAgAAAA==.Darc:BAAALgAECgQJBgAAAA==.Daredayo:BAAALgAECgEJAQAAAA==.Darkkubo:BAAALgAECgEJAQAAAA==.Darklite:BAAALgADCgYJEgAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Davinci:BAAALgADCgEJAQAAAA==.Day:BAABLgAECn8lAAIJAAkJHhkWKwAxAgAJAAkJHhkWKwAxAgAAAA==.Dayztocome:BAAALgADCgEJAQAAAA==.',
De='Decaydence:BAABLgAECn8WAAIPAAgJewkVCwDdAAAPAAgJewkVCwDdAAAAAA==.Dejno:BAABLgAECn8YAAITAAcJMiDjLACfAQATAAcJMiDjLACfAQAAAA==.Deleted:BAAALgAECgEJAQABLgAECgkJLAAPADwlAA==.Demonicly:BAABLgAECn8WAAIMAAgJFRLiDgBiAQAMAAgJFRLiDgBiAQAAAA==.Demonred:BAAALgADCgYJBgAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgAECgQJBAAAAA==.Dezign:BAACLgAFFH8ZAAIKAAcJMxvOJQDiAQAKAAcJMxvOJQDiAQAuAAQKfykAAgoACQl2IOooAM8CAAoACQl2IOooAM8CAAAA.Dezígn:BAABLgAFFH8IAAIHAAQJAhKeVAAdAQAHAAQJAhKeVAAdAQABLgAFFAcJGQAKADMbAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMgAAYJQQxuUQC9AAAgAAUJvA5uUQC9AAAXAAEJVQIkwAAYAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECgkJLAAHAL8jAA==.',
Do='Dolgorukov:BAABLgAECn8vAAIJAAkJXhNORQDSAQAJAAkJXhNORQDSAQAAAA==.Dologony:BAABLgAECn8jAAIBAAkJmg4sQACRAQABAAkJmg4sQACRAQAAAA==.',
Dr='Dracigor:BAAALgAECgQJBgAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgUJEQAAAA==.Drakhan:BAAALgADCgIJAgAAAA==.Dre:BAAALgAECgMJCAAAAA==.Dreåm:BAAALgADCgQJBAABLgAECgkJLAAHAL8jAA==.Drikken:BAABLgAECn9GAAQNAAkJDB3CAwBXAQANAAkJoBvCAwBXAQAMAAUJ2xvgFAAHAQALAAUJgBZGMAAGAQAAAA==.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAILAAkJVxgdGADCAQALAAkJVxgdGADCAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECgkJLAAPADwlAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8lAAMaAAcJ9gy7GQAFAQAaAAUJMg67GQAFAQAPAAcJWwdpygDwAAAAAA==.Duressa:BAAALgAECgcJBwAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMSAAgJIhX0CQCmAQASAAgJIhX0CQCmAQAHAAIJZwswDQFbAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgUJBwAAAA==.Effinfu:BAABLgAECn8pAAIgAAkJ3RK7AQBHAQAgAAkJ3RK7AQBHAQAAAA==.',
Ei='Eitent:BAABLgAECn8wAAMUAAkJux3FDQCqAgAUAAkJux3FDQCqAgAVAAcJuhIRdgCOAQABLgAFFAMJCAAfAGITAA==.Eitentormu:BAAALgAECggJCAABLgAFFAMJCAAfAGITAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgcJHQAUALEfAA==.Ellesthara:BAAALgAECgcJEwAAAA==.Ellysiaa:BAABLgAECn8WAAIEAAYJLQWeMgCVAAAEAAYJLQWeMgCVAAAAAA==.Elrïc:BAAALgAECgUJBgAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8zAAMFAAkJrxV+GQAAAgAFAAkJrxV+GQAAAgABAAcJMA0rWAAwAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgADCgcJHAAAAA==.Enyxea:BAABLgAECn8ZAAIDAAkJQBaaKgARAgADAAkJQBaaKgARAgAAAA==.',
Ep='Ephemera:BAAALgAECgYJEQAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgAECgEJAgAAAA==.',
Es='Esmeray:BAEBLgAECn8eAAIfAAkJIxYmEgBUAgAfAAkJIxYmEgBUAgABLgAECgkJGwAQANURAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAABLgAECn8kAAIhAAkJVh8LBADHAgAhAAkJVh8LBADHAgAAAA==.Eyewana:BAABLgAECn8kAAILAAkJchKbHQCPAQALAAkJchKbHQCPAQAAAA==.',
Ez='Ezzka:BAABLgAECn8nAAIPAAkJCR1pIACHAgAPAAkJCR1pIACHAgAAAA==.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJDgAAAA==.Fangalor:BAAALgAECgEJBAAAAA==.Farnsworth:BAABLgAECn8eAAQHAAkJ4R0KHwBqAgAHAAgJ+x0KHwBqAgASAAMJGBxCIQCkAAAdAAEJNBPrOQBBAAAAAA==.Farzix:BAABLgAECn8qAAIIAAkJKQn3PABCAQAIAAkJKQn3PABCAQAAAA==.Façade:BAABLgAECn8mAAIPAAkJDxMYYACpAQAPAAkJDxMYYACpAQAAAA==.',
Fe='Feelgood:BAAALgAECgcJCwAAAA==.Fefifiona:BAACLgAFFH8FAAIfAAIJOA2fQAB3AAAfAAIJOA2fQAB3AAAuAAQKfxkAAh8ACQkqF2sQAGoCAB8ACQkqF2sQAGoCAAAA.Fefifredrich:BAAALgAECgMJAwABLgAFFAIJBQAfADgNAA==.Fefifuredric:BAAALgAECgQJBQABLgAFFAIJBQAfADgNAA==.Felvira:BAABLgAECn8dAAMNAAgJPgTO1ACLAAANAAYJbQPO1ACLAAALAAUJWwRCWgBZAAAAAA==.',
Fi='Finnw:BAABLgAECn8dAAIUAAcJsR/mEACPAgAUAAcJsR/mEACPAgAAAA==.Firelite:BAABLgAECn8oAAIIAAkJYA/9OwBFAQAIAAkJYA/9OwBFAQAAAA==.',
Fl='Flairlock:BAABLgAECn8/AAMdAAkJZyGxAgCfAgAdAAkJZyGxAgCfAgASAAIJBhW3PAA5AAAAAA==.Flee:BAABLgAECn8iAAIQAAkJqRoKDwA7AgAQAAkJqRoKDwA7AgAAAA==.Flexo:BAAALgAECgEJAQABLgAECgkJHgAHAOEdAA==.',
Fo='Fookster:BAABLgAECn8ZAAIKAAkJyhPfQAAaAgAKAAkJyhPfQAAaAgAAAA==.Forsetee:BAABLgAFFH8GAAIgAAIJTReHRACQAAAgAAIJTReHRACQAAAAAA==.',
Fr='Frowdawn:BAABLgAECn87AAIRAAkJUxCwBwDcAQARAAkJUxCwBwDcAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAACAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgAPACoaAA==.',
Ga='Ga:BAAALgAECgIJAgAAAA==.Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAABLgAECn8bAAIZAAYJUxLgAgDiAAAZAAYJUxLgAgDiAAAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJMAAPANYiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.',
Gi='Gilas:BAAALgADCgYJEAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8vAAIBAAkJ4gvhRgB0AQABAAkJ4gvhRgB0AQAAAA==.',
Go='Googoobler:BAABLgAECn8iAAILAAgJ7AeqLwAJAQALAAgJ7AeqLwAJAQAAAA==.Goudaluck:BAAALgADCgUJBwABLgAECgkJNgAJAKoiAA==.Goudanight:BAAALgAECgMJBQABLgAECgkJNgAJAKoiAA==.Goudavibes:BAAALgAECgEJAQABLgAECgkJNgAJAKoiAA==.',
Gr='Greenmagus:BAAALgAECgQJBAAAAA==.Grenadon:BAABLgAECn8YAAIGAAYJ3AMSCQBjAAAGAAYJ3AMSCQBjAAAAAA==.Gridimbor:BAAALgAECgEJAQAAAA==.Grimlilith:BAABLgAECn8bAAQdAAgJ/wSbEQATAQAdAAgJ9gSbEQATAQAHAAMJBAMCMQE5AAASAAEJAAAogQALAAAAAA==.Grimmhoof:BAAALgAECgIJAgAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gulem:BAAALgADCgYJBgAAAA==.Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn9AAAIbAAkJOx0NDQCCAgAbAAkJOx0NDQCCAgAAAA==.Hakitua:BAABLgAECn8mAAIMAAkJ2w1pDgBqAQAMAAkJ2w1pDgBqAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDgAAAA==.Hatshepsut:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn9AAAITAAkJ1A/3KAC2AQATAAkJ1A/3KAC2AQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAABLgAECn8qAAQZAAkJ3iXGAABpAwAZAAkJ3iXGAABpAwATAAcJ7hyOHgD6AQAWAAMJvxAeTQCbAAABLgAECgkJLAAHAL8jAA==.Heis:BAABLgAECn8bAAITAAYJsRfzAgBYAQATAAYJsRfzAgBYAQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8xAAIVAAkJABcwQwD9AQAVAAkJABcwQwD9AQAAAA==.',
Hi='Hiko:BAABLgAECn8ZAAMgAAgJFg96KgBiAQAgAAgJFg96KgBiAQAXAAEJggNDugAfAAAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMDAAYJJgqFAgC9AQADAAYJJgqFAgC9AQAIAAUJFB/mHQAuAQAuAAQKfyEAAwgACQlzIWYDAG0DAAgACQlzIWYDAG0DAAMABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgADACYKAA==.Holyangus:BAAALgAECgUJDQAAAA==.Holyfawn:BAAALgADCgEJAQAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.Hulahoof:BAAALgAECgYJBgAAAA==.',
Ib='Ibbert:BAAALgADCggJFwAAAA==.',
Ic='Icculus:BAABLgAECn8lAAIJAAgJJxkqOQD5AQAJAAgJJxkqOQD5AQAAAA==.Iceticles:BAAALgAECgUJBQAAAA==.',
Il='Illuyanka:BAAALgAECgIJAgAAAA==.',
Im='Imaresmashy:BAAALgAECgIJAgABLgAECgkJJAACAAAAAA==.Impasse:BAAALgAECgkJCAAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8+AAIgAAkJaSTgAQBKAwAgAAkJaSTgAQBKAwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgACAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Iy='Iyrus:BAAALgAECgkJCQAAAA==.',
Ja='Jacolynn:BAABLgAECn8ZAAIYAAcJBRLsKwBXAQAYAAcJBRLsKwBXAQAAAA==.Jaenei:BAAALgAECgcJDwAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Ji='Jinrok:BAAALgAECgUJBgAAAA==.',
Jo='Joansnow:BAAALgAECgcJBwABLgAECgkJIQAYAIQSAA==.Joatmoa:BAACLgAFFH8GAAIEAAMJNRTlDQDbAAAEAAMJNRTlDQDbAAAuAAQKfxQAAgQACQmIHP8PALcBAAQACQmIHP8PALcBAAAA.Joeexotics:BAAALgADCgkJDAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECggJEgAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCgcJHQAAAA==.',
Ka='Kaelnis:BAAALgAECggJEgAAAA==.Kaimargonar:BAABLgAECn8bAAISAAgJ+RKmCwCFAQASAAgJ+RKmCwCFAQAAAA==.Kaitoi:BAABLgAECn8jAAMEAAkJ7BzPBACtAgAEAAkJ7BzPBACtAgAGAAUJKwi0TAB4AAAAAA==.Kalinth:BAAALgADCgIJAgAAAA==.Kallah:BAACLgAFFH8hAAIUAAgJ8R4ZCAA/AgAUAAgJ8R4ZCAA/AgAuAAQKfzcAAhQACQnsI44BAGsDABQACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn9BAAQiAAkJHBkSCQBZAgAiAAgJjxkSCQBZAgAjAAkJnBGJBwDCAQAkAAEJMRnTCwBEAAAAAA==.Kamakizeg:BAACLgAFFH8FAAIVAAIJIQ1SkwCNAAAVAAIJIQ1SkwCNAAAuAAQKfy8AAhUACQl3FA1RANUBABUACQl3FA1RANUBAAAA.Kamayla:BAAALgADCgYJBgAAAA==.Karnus:BAAALgADCgUJBQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8oAAIKAAkJdh2kIQCXAgAKAAkJdh2kIQCXAgAAAA==.Katimalice:BAAALgAECgEJAQAAAA==.',
Ke='Kestrelle:BAAALgAECgcJEwABLgAECgkJVgABAFQSAA==.Keyzeus:BAABLgAECn8lAAMjAAgJCxibBgDjAQAjAAgJCxibBgDjAQAkAAEJ5xsAhwBOAAAAAA==.',
Kh='Khas:BAAALgADCgkJHAAAAA==.Khui:BAACLgAFFH8bAAIYAAYJSyUDCgBoAgAYAAYJSyUDCgBoAgAuAAQKfyUAAxgACAkWJcACAFcDABgACAkWJcACAFcDABcAAwkwGLdSAL4AAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBwAAAA==.Kipziep:BAAALgAECgIJAgAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8aAAMPAAgJoxZRDQBxAQAPAAcJoxZRDQBxAQAeAAEJAAB8VgAAAAAuAAQKfygAAg8ACQn9INMSAAsDAA8ACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8rAAIYAAkJ/RciFgBpAgAYAAkJ/RciFgBpAgABLgAFFAgJGgAPAKMWAA==.',
Ko='Koltharaz:BAAALgAECgEJAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAACAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krankthas:BAAALgAECgIJAgABLgAECgIJBAACAAAAAA==.Krazylock:BAAALgAECgMJBQAAAA==.Krazysniper:BAABLgAECn8oAAMJAAgJCRy0MAAZAgAJAAcJEB+0MAAZAgAlAAEJ4wmKYgA3AAAAAA==.Kreepa:BAAALgADCgIJAgAAAA==.Krokk:BAABLgAECn8UAAIIAAcJ9QdiVQDlAAAIAAcJ9QdiVQDlAAAAAA==.Kruulock:BAAALgADCgcJBwAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAFFAEJAQABLgAFFAUJFwACAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMVAAgJFh66KgB5AgAVAAgJFh66KgB5AgAUAAYJOBheOwBbAQAAAA==.Lacosanostra:BAAALgAECgYJDwAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lancedragon:BAAALgADCgEJAQAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgAVABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8nAAIJAAcJ5hm2TwCzAQAJAAcJ5hm2TwCzAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgkJJAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lezsul:BAAALgAECgIJAgAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8fAAIVAAcJAhIflgBIAQAVAAcJAhIflgBIAQAAAA==.Lightguard:BAAALgAECgkJEgAAAA==.Lighthouse:BAABLgAECn8vAAIVAAkJlxtFNQArAgAVAAkJlxtFNQArAgAAAA==.Lileth:BAAALgAECgUJBQAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAINAAgJ9RVJWwB2AQANAAgJ9RVJWwB2AQAAAA==.Lolhahabaha:BAAALgAECggJDQAAAA==.Loopie:BAAALgADCgYJCgAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8XAAIeAAcJlxVxIwA4AQAeAAcJlxVxIwA4AQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgkJHwAJAPgfAA==.',
Ly='Lypally:BAABLgAECn9JAAIVAAkJHxknAgAwAgAVAAkJHxknAgAwAgAAAA==.',
['Lï']='Lïllïth:BAAALgAECgYJBwAAAA==.Lïly:BAAALgADCggJEAABLgAECgkJJAACAAAAAA==.',
['Ló']='Lóla:BAABLgAECn8wAAINAAkJziMYCAAPAwANAAkJziMYCAAPAwAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8oAAMQAAgJGRaLBQBkAgAQAAgJGRaLBQBkAgARAAYJOw8xAwBvAQAuAAQKfyEAAxAACAlGHtkMAMsCABAACAlGHtkMAMsCABEAAQnoGt8aAFEAAAAA.Mahimahi:BAAALgAECggJCAAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8fAAImAAkJphVTCgAUAgAmAAkJphVTCgAUAgAAAA==.Mariacuras:BAABLgAECn8WAAIUAAkJ7AqDMQCRAQAUAAkJ7AqDMQCRAQAAAA==.Marle:BAABLgAECn87AAINAAkJ1hh3AQADAgANAAkJ1hh3AQADAgAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgAECgUJBwAAAA==.Martis:BAAALgAECgYJBwAAAA==.Marynne:BAABLgAECn9WAAMBAAkJVBKMLgDrAQABAAkJVBKMLgDrAQAFAAEJSwKerAAMAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8zAAMMAAkJvxc0BwASAgAMAAkJUBc0BwASAgALAAIJ7xmVBgCNAAAAAA==.',
Mc='Mcdo:BAAALgAFFAIJAgABLgAFFAYJFAAnALAhAA==.Mctank:BAAALgAECgEJAQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8wAAMbAAgJhQ8nKgCAAQAbAAgJhQ8nKgCAAQAOAAUJxQwWTgCqAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAABLgAECn8lAAMVAAYJVhyJBACQAQAVAAYJVhyJBACQAQAUAAUJJQ/cVwDXAAAAAA==.Meliza:BAAALgAECgEJAQABLgAECgUJBgACAAAAAA==.Merrikeath:BAABLgAECn8cAAIPAAkJMggWCQD+AAAPAAkJMggWCQD+AAAAAA==.Merriklade:BAABLgAECn8zAAMZAAkJAA8oFwCKAQAZAAkJRw4oFwCKAQATAAgJzQozOwBZAQAAAA==.Merrikwolf:BAAALgAECgYJBgAAAA==.',
Mi='Missyjelliot:BAAALgAECggJDwAAAA==.',
Mo='Monster:BAAALgADCgEJAQAAAA==.Moof:BAAALgADCgEJAQAAAA==.Morbidstyle:BAAALgAECgQJBQAAAA==.Morchuk:BAAALgADCgMJAwAAAA==.Morigith:BAAALgAECgQJBAABLgAECgUJBgACAAAAAA==.Morthos:BAAALgAECgUJCAAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgcJHQAUALEfAA==.',
My='Myora:BAEBLgAECn8bAAIQAAkJ1RG8EwAGAgAQAAkJ1RG8EwAGAgAAAA==.Mythundirus:BAAALgADCgMJAwAAAA==.',
['Mà']='Màrli:BAABLgAECn8YAAMeAAkJchHJAQB8AQAeAAkJchHJAQB8AQAaAAcJ8QiDGgD8AAAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8gAAIhAAkJWhLcEQCoAQAhAAkJWhLcEQCoAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQAWADUeAA==.Nakasid:BAACLgAFFH8KAAIOAAMJYxEBIgCqAAAOAAMJYxEBIgCqAAAuAAQKfz4ABA4ACQmRGfcAACMCAA4ACQmRGfcAACMCABsABwkVCNQ5ACIBAB8ABAlbCntcAI0AAAAA.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Naura:BAAALgADCgMJAwAAAA==.Navane:BAAALgAECgUJBwAAAA==.',
Ne='Necromaniac:BAAALgAECgEJAQAAAA==.Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8rAAINAAkJsBDpQwC8AQANAAkJsBDpQwC8AQAAAA==.Nevaehstar:BAACLgAFFH8FAAIcAAMJZg+tAADhAAAcAAMJZg+tAADhAAAuAAQKfz4AAhwACQl5IlsAAC8DABwACQl5IlsAAC8DAAAA.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJDQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8uAAIOAAkJOxQKIADDAQAOAAkJOxQKIADDAQAAAA==.Nikolia:BAAALgAECgYJDwAAAA==.Ninetynine:BAAALgADCgMJBQAAAA==.Nini:BAABLgAECn8nAAIFAAgJvgKcXQCgAAAFAAgJvgKcXQCgAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJEAALANcSAA==.Nokru:BAAALgADCgMJBQAAAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgcJDAAAAA==.',
Nz='Nzuul:BAAALgAECgUJDwAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAwAAAA==.',
Om='Ominous:BAAALgAECgMJAwAAAA==.',
On='Onram:BAAALgAECgEJAQAAAA==.',
Op='Oppaissiah:BAABLgAECn9EAAMZAAkJ6iNPAgAlAwAZAAkJlSNPAgAlAwATAAkJ8R/7CQDDAgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAIkAAYJawJudgB5AAAkAAYJawJudgB5AAABLgAECgkJEgACAAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.Orman:BAAALgAFFAEJAQAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAABLgAECgkJNQAVANcKAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJDAAAAA==.Pandamared:BAAALgADCggJCgAAAA==.Papasbich:BAABLgAECn8lAAILAAcJaAlhBADVAAALAAcJaAlhBADVAAABLgAFFAMJBwAVAHQEAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Ph='Phantazm:BAAALgADCgEJAQAAAA==.Phenol:BAAALgADCgUJBQAAAA==.Phoxie:BAAALgAECgEJAQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchoplust:BAAALgAECgEJAQAAAA==.Porkchopw:BAAALgAECgcJAgAAAA==.Porkribs:BAAALgAFFAMJBAAAAA==.',
Pr='Presap:BAABLgAECn8zAAMBAAkJBCJuBQBhAwABAAkJBCJuBQBhAwAFAAEJAACrdgBJAAABLgAECgkJGQAiAKwcAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAABLgAECn8bAAIEAAYJ6xaVAQA3AQAEAAYJ6xaVAQA3AQAAAA==.Pumdmuc:BAACLgAFFH8NAAIOAAQJCRxTEQBEAQAOAAQJCRxTEQBEAQAuAAQKf0UAAw4ACQnlIdoGAN8CAA4ACQnlIdoGAN8CABsABwkqBbVTAMMAAAAA.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJEAAAAA==.',
Qu='Quikglaives:BAAALgAFFAMJBAAAAA==.Quille:BAABLgAECn8fAAIJAAgJSiPzDgDZAgAJAAgJSiPzDgDZAgAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIhAAkJrRJqEQCuAQAhAAkJrRJqEQCuAQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgMJBAAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJDAAAAA==.Redrek:BAAALgADCggJHgAAAA==.Redsbank:BAAALgADCgMJAwAAAA==.Redshunter:BAAALgADCgcJEgAAAA==.Redsknight:BAAALgADCgkJCQAAAA==.Redsmonk:BAAALgADCgcJFQAAAA==.Redwinter:BAAALgAECgIJBAABLgAECggJHwATAPcbAA==.Reikisong:BAAALgAECgUJCAAAAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reylia:BAAALgAECgQJBAAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhagurion:BAAALgAFFAEJAQAAAA==.Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8lAAIBAAgJJhSgLwDlAQABAAgJJhSgLwDlAQAAAA==.',
Ro='Rockmonsta:BAAALgAECgUJCQAAAA==.Rockrat:BAAALgADCgEJAQAAAA==.Rodeo:BAABLgAECn8sAAIFAAkJABCiIwCtAQAFAAkJABCiIwCtAQAAAA==.Rotgutwiskey:BAAALgAECgIJAgAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.Royan:BAAALgAECgcJDQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAINAAYJeQ6eegA4AQANAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAECgcJCgAAAA==.Sadnhornless:BAAALgAECgEJAwAAAA==.Saeti:BAACLgAFFH8TAAMEAAQJzxzICQARAQAEAAMJRB7ICQARAQAFAAEJbxiNSQBMAAAuAAQKfz4ABQQACQlIIZYHAG8CAAQACQlAIZYHAG8CAAUABgmdGzIrAHwBAAYABAk2HlIrAAQBAAEABAkUFoqIAKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sapplesauce:BAABLgAECn8XAAIQAAgJ5Bc9HgCkAQAQAAgJ5Bc9HgCkAQAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAACLgAFFH8JAAMBAAMJRgdoUQB9AAABAAMJRgdoUQB9AAAFAAEJ4wYnUQA0AAAuAAQKf1cAAwEACQkgH/ALAAEDAAEACQkgH/ALAAEDAAUABgmbE5Y4ADEBAAAA.',
Sh='Shadý:BAABLgAECn8vAAIJAAkJ5AoTVgCiAQAJAAkJ5AoTVgCiAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECgkJLAAPADwlAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQSAAgJLBqNCwCIAQAHAAgJ1hcKRADPAQASAAcJeBiNCwCIAQAdAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn9BAAITAAkJohxfDgCLAgATAAkJohxfDgCLAgAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sianu:BAAALgAECgcJBwABLgAECgkJVgABAFQSAA==.Sidarya:BAABLgAECn8YAAMOAAgJgRcDGgD7AQAOAAgJgRcDGgD7AQAbAAIJZgcAEgAtAAAAAA==.Sidera:BAAALgAECggJDgAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAACLgAFFH8UAAMTAAQJVhz9FQBeAQATAAQJVhz9FQBeAQAWAAEJPAxiQgBDAAAuAAQKfx4AAxYACQmjFs4ZACUBABMABwlxFW5EADQBABYABgkoEs4ZACUBAAAA.Silveric:BAAALgADCgYJCQAAAA==.Silverserket:BAAALgAECgIJBAAAAA==.Silverserqet:BAABLgAECn8UAAIJAAcJswpLhAA2AQAJAAcJswpLhAA2AQAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn9SAAMDAAkJShZEAgDsAQADAAkJShZEAgDsAQAIAAgJQAiaSgAKAQAAAA==.Skyscales:BAEALgAECgcJBwABLgAECgkJUgADAEoWAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.Slipknaught:BAAALgAECgQJAwABLgAECgkJIQAYAIQSAA==.',
Sm='Smileyriley:BAABLgAECn8aAAIFAAcJzQXfTwDOAAAFAAcJzQXfTwDOAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBQABLgAECgcJDgACAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAABLgAECn8XAAIYAAUJCwRzlQBtAAAYAAUJCwRzlQBtAAAAAA==.Sooki:BAAALgAECgIJBAAAAA==.Sorilea:BAAALgADCgcJCAAAAA==.Sorlis:BAAALgAECgcJEwAAAA==.Soulber:BAABLgAECn8ZAAMPAAkJbhTjWAC7AQAPAAkJkhPjWAC7AQAeAAIJnxxUPACgAAAAAA==.Sourdew:BAABLgAECn8eAAIXAAcJtB7ZGQDiAQAXAAcJtB7ZGQDiAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8ZAAMiAAkJrBwjBADzAgAiAAkJrBwjBADzAgAjAAEJAAA/LwAAAAAAAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwACAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgUJCwAAAA==.Stefeana:BAAALgAECgYJBgAAAA==.Stelle:BAABLgAECn8XAAIfAAgJBBEYJABzAQAfAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgIJAgAAAA==.Stylos:BAABLgAECn9BAAImAAgJPBclDADwAQAmAAgJPBclDADwAQAAAA==.Stãrburst:BAABLgAECn8UAAMDAAgJZQr4ewDsAAADAAcJswf4ewDsAAAIAAEJUASqvwAeAAAAAA==.',
Su='Subrinea:BAAALgAECgUJBQABLgAFFAMJBQAcAGYPAA==.',
Sy='Sylven:BAAALgADCgYJBgABLgAECgkJLAAHAL8jAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECgcJEgAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQeAAgJNBm8EwDXAQAeAAgJVBi8EwDXAQAPAAgJBQ8oZwDAAQAaAAEJAACfGgAeAAABLgAECgkJDgACAAAAAA==.Tegmage:BAAALgAECgUJBQABLgAECgkJDgACAAAAAA==.Tempestrike:BAAALgAFFAIJAgAAAA==.Terentia:BAEALgAECgUJBQABLgAECgkJGwAQANURAA==.',
Th='Thadind:BAAALgAECgQJBAAAAA==.Thalodrim:BAAALgAECgEJAQABLgAECgkJHgAHAOEdAA==.Tharelly:BAABLgAECn8XAAIKAAkJrxi6OwArAgAKAAkJrxi6OwArAgAAAA==.Thasserian:BAAALgADCgIJAgABLgAECgkJLAAHAL8jAA==.Theholymatt:BAACLgAFFH8VAAMUAAYJihZBFgB2AQAUAAUJAxRBFgB2AQAVAAQJzRnKGgDDAAAuAAQKfz0AAxUACQkoJEcIACkDABUACQkoJEcIACkDABQABwnnJEEPAJsCAAAA.Thendari:BAABLgAECn+CAAISAAkJixlOAAA3AgASAAkJixlOAAA3AgAAAA==.Theodus:BAABLgAECn81AAIKAAkJhxlIOAA3AgAKAAkJhxlIOAA3AgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAIkAAgJfxorHAD0AQAkAAgJfxorHAD0AQABLgAFFAYJFQAUAIoWAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn9JAAMWAAkJgSQ4AAAUAwAWAAkJRCQ4AAAUAwATAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8SAAIUAAUJwBraEQClAQAUAAUJwBraEQClAQAuAAQKfz0AAhQACQn3IDgFAEADABQACQn3IDgFAEADAAAA.Tislam:BAABLgAECn8ZAAIHAAkJHg6zaABrAQAHAAkJHg6zaABrAQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQWAAkJNR7NBACaAgAWAAkJFhrNBACaAgAZAAcJpSCYDwDuAQATAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn9RAAIOAAkJPB12AADEAgAOAAkJPB12AADEAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIZAAkJJBMGFACvAQAZAAkJJBMGFACvAQABLgAECgQJBAACAAAAAA==.Torolf:BAAALgAECgUJCwAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgMJBAAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8gAAMIAAgJ5BRyCAAsAgAIAAgJ5BRyCAAsAgADAAEJYAwCegBLAAAuAAQKf0gAAggACQnMIswEABQDAAgACQnMIswEABQDAAAA.',
Ts='Tsonokwabain:BAABLgAECn8mAAQaAAkJhyKlAQAYAwAaAAkJhyKlAQAYAwAeAAEJah2JVABIAAAPAAEJmALGpgEYAAAAAA==.Tsunami:BAAALgADCgYJCAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn83AAQiAAkJ7hR/DgDmAQAiAAkJ7hR/DgDmAQAjAAEJ6gYPKQAqAAAkAAEJWQR3DwAgAAAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAIQAAkJ4QXSKABRAQAQAAkJ4QXSKABRAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAAALgAFFAEJAwAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAINAAgJOxgFTgCcAQANAAgJOxgFTgCcAQAAAA==.Vaerryn:BAABLgAECn8mAAQaAAgJMyOABgA8AgAaAAcJFiOABgA8AgAPAAMJcBv80gDkAAAeAAIJQyCDUQBPAAAAAA==.Vaethund:BAAALgAECgkJEwAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAAMAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Valkz:BAAALgADCgEJAQAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAABLgAECn8ZAAMlAAkJ5gw1KABeAQAlAAcJxQw1KABeAQAJAAgJ1QovGwBjAAAAAA==.Vassyra:BAEBLgAECn8rAAIjAAkJJBdOBQAOAgAjAAkJJBdOBQAOAgABLgAECgkJGwAQANURAA==.',
Ve='Velara:BAAALgAECgcJCAAAAA==.Velesyn:BAABLgAECn8cAAMMAAgJUx9UBwAOAgAMAAcJKCBUBwAOAgANAAIJtxH7/QBOAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.Venekor:BAAALgADCgUJBQAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Villesen:BAAALgAECgQJCwABLgAECgkJMgAVAEIfAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.Vitoria:BAAALgAECgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAACLgAFFH8IAAIfAAMJYhMHMgDGAAAfAAMJYhMHMgDGAAAuAAQKfygAAx8ACQlbGWgMAKcCAB8ACQlbGWgMAKcCABsACAnVFwYaAPUBAAAA.Volundr:BAABLgAECn9AAAIZAAkJ7xgNDgAKAgAZAAkJ7xgNDgAKAgAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECgkJGQAXAJAhAA==.',
Vy='Vynel:BAAALgAECgYJCAABLgAECgkJLAAHAL8jAA==.Vynirion:BAABLgAECn8UAAIKAAcJqxJUpACPAQAKAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAABLgAECn8eAAIQAAkJbAYrJABzAQAQAAkJbAYrJABzAQAAAA==.Wardellmo:BAAALgAECgEJAQAAAA==.Wargtar:BAABLgAECn82AAIQAAgJISD8DQBIAgAQAAgJISD8DQBIAgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8YAAMOAAcJFhGKNgAmAQAOAAcJ9w+KNgAmAQAfAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJDwAAAA==.',
Wh='Whatcow:BAAALgAFFAEJAQAAAA==.Whiteback:BAAALgADCgUJBQAAAA==.Whiterrina:BAAALgADCgkJCgAAAA==.',
Wi='Window:BAAALgAECgEJAQAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8iAAMFAAkJ9AjhMgBPAQAFAAkJ9AjhMgBPAQABAAUJEgfQiwCfAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAIJAAkJywobVgBmAQAJAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn83AAMDAAkJFCMoDQDuAgADAAkJFCMoDQDuAgAIAAcJyRiaKACqAQAAAA==.',
Xk='Xkwizet:BAABLgAECn8aAAIKAAgJPgcsoQA5AQAKAAgJPgcsoQA5AQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgAECgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8zAAIVAAkJWiVTBQBKAwAVAAkJWiVTBQBKAwAAAA==.',
Yi='Yiffweaver:BAABLgAECn80AAIgAAkJKAw0AQCPAQAgAAkJKAw0AQCPAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn80AAIhAAkJfhNXEAC/AQAhAAkJfhNXEAC/AQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAABLgAECn8dAAIFAAkJpwciBQDXAAAFAAkJpwciBQDXAAAAAA==.',
Za='Zarhianna:BAABLgAECn8jAAIFAAkJgBBHIgC3AQAFAAkJgBBHIgC3AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.Zephnor:BAAALgAECgYJBwAAAA==.',
Zm='Zmona:BAABLgAECn8xAAIVAAkJHg+aZwCgAQAVAAkJHg+aZwCgAQAAAA==.',
Zo='Zorsche:BAAALgADCgcJEQAAAA==.',
Zu='Zulrok:BAABLgAECn8tAAITAAkJbB3wEgBbAgATAAkJbB3wEgBbAgAAAA==.',
['Åv']='Åviendha:BAAALgADCgcJCAAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAIKAAcJ0hZswwBfAQAKAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAABLgAECn8VAAIVAAYJ6wNdDgGnAAAVAAYJ6wNdDgGnAAAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8uAAIKAAkJUiPnFADcAgAKAAkJUiPnFADcAgAAAA==.',
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
